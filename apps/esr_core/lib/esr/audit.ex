defmodule Esr.Audit do
  @moduledoc """
  Telemetry handler that fans `[:esr, :invoke, :stop]` and
  `[:esr, :invoke, :error]` events out to **both**:

  1. `Phoenix.PubSub.broadcast(EsrCore.PubSub, "esr:audit:stream",
     {:audit_event, event})` — for view fan-outs (LiveView `/admin`,
     future Feishu admin, CLI tail). This is the §5.7.6-legitimate
     broadcast (audience is undefined observers).
  2. `GenServer.cast(Esr.Audit.Writer, {:write, row})` — for the
     async SQLite write.

  The handler itself only does these two non-blocking ops, never
  touches the DB directly. That's enforced by invariant #6 (grep
  `Esr.Repo|Repo.insert|exqlite` in `audit.ex` must be empty).

  ## attach/0

  Called from `EsrCore.Application.start/2` after the Writer is up.
  Idempotent — `:telemetry.attach/4` overwrites prior handlers of the
  same id.
  """

  @handler_id "esr-audit"
  @audit_stream_topic "esr:audit:stream"

  # Phase 3d hard flip (per P3-D6 + #B5):
  # - [:esr, :authz, :granted] / :denied REPLACE the Phase 1-2 :stub_grant
  #   marker. New audit rows carry "granted" / "denied" in the authz
  #   column; check_invariants #9 enforces :stub_grant atom no longer
  #   appears in code (only allowed in this audit.ex if we needed
  #   backward-compat decoding, which we don't — Phase 3d hard flip).
  @events [
    [:esr, :invoke, :stop],
    [:esr, :invoke, :error],
    [:esr, :authz, :granted],
    [:esr, :authz, :denied],
    # Phase 3d quality hotfix: chat reply dispatch fail visibility
    # (was silent before — real-claude e2e exposed wrong session_uri
    # disappearing into the void).
    [:esr, :chat, :reply_dispatch_failed],
    # Phase 4-completion Spec 04: per-Kind state persistence events.
    [:esr, :persistence, :restored],
    [:esr, :persistence, :written],
    [:esr, :persistence, :failed],
    # Phase 4-plus follow-up (2026-05-17): CC-side hook reports.
    # Audit table records the event so operators have a queryable
    # history even after the in-memory LV panel rolls over.
    [:esr, :cc_bridge, :event]
  ]

  @doc """
  Attach telemetry handlers. Idempotent — already-attached returns `:ok`.
  """
  def attach do
    case :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle_event/4, nil) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  @doc false
  def handle_event(event, measurements, metadata, _config) do
    audit_event = %{
      event: event,
      measurements: measurements,
      metadata: serialise_metadata(metadata),
      at: DateTime.utc_now()
    }

    # Path 1: PubSub broadcast for LV / future view fan-outs (§5.7.6
    # legitimate broadcast — audience is undefined observers).
    Phoenix.PubSub.broadcast(EsrCore.PubSub, @audit_stream_topic, {:audit_event, audit_event})

    # Path 2: async write to SQLite via the batch writer.
    GenServer.cast(Esr.Audit.Writer, {:write, build_row(event, measurements, metadata)})
  end

  @doc "Topic for LV / view subscribers to subscribe to."
  def stream_topic, do: @audit_stream_topic

  # ---------------------------------------------------------------------
  # The PubSub message keeps the raw event shape for view rendering;
  # the SQLite row uses the column shape required by the migrations.

  defp build_row([:esr, :invoke, :stop], %{duration_us: us}, meta) do
    %{
      trace_id: nil,
      caller: uri_to_str(Map.get(meta, :caller)),
      target: uri_to_str(Map.get(meta, :target)),
      action: stringify(Map.get(meta, :action)),
      args: nil,
      result: nil,
      duration_us: us,
      # Phase 3d: authz column from real cap check. :granted event has
      # already fired before this :invoke :stop, so we record "granted"
      # for success. The :denied path never reaches :invoke :stop
      # because dispatch short-circuits with {:error, :unauthorized}.
      authz: "granted",
      exception: nil,
      inserted_at: DateTime.utc_now()
    }
  end

  defp build_row([:esr, :invoke, :error], %{duration_us: us}, meta) do
    reason = Map.get(meta, :reason)

    # Distinguish authz denied from other errors so the audit row's
    # authz column is meaningful for operators debugging permissions.
    authz =
      case reason do
        :unauthorized -> "denied"
        _ -> "n/a"
      end

    %{
      trace_id: nil,
      caller: uri_to_str(Map.get(meta, :caller)),
      target: uri_to_str(Map.get(meta, :target)),
      action: nil,
      args: nil,
      result: nil,
      duration_us: us,
      authz: authz,
      # JSON-encode for ecto_sqlite3 schemaless insert_all (see Esr.DLQ).
      exception: Jason.encode!(%{reason: inspect(reason)}),
      inserted_at: DateTime.utc_now()
    }
  end

  # Phase 3d: :authz events also persist a row so the audit log shows
  # the granted/denied decision separately from invoke success/error.
  defp build_row([:esr, :authz, decision], _measurements, meta) do
    %{
      trace_id: nil,
      caller: uri_to_str(Map.get(meta, :caller)),
      target: uri_to_str(Map.get(meta, :target)),
      action: stringify(Map.get(meta, :action)),
      args: nil,
      result: nil,
      duration_us: 0,
      authz: Atom.to_string(decision),
      exception: nil,
      inserted_at: DateTime.utc_now()
    }
  end

  # Phase 3d quality hotfix: chat reply dispatch failure (agent's chat/send
  # targeting a non-existent session). Persisted so admin can see why a
  # claude reply silently disappeared.
  defp build_row([:esr, :chat, :reply_dispatch_failed], _measurements, meta) do
    %{
      trace_id: nil,
      caller: Map.get(meta, :agent),
      target: "#{Map.get(meta, :target_session)}/behavior/chat/send",
      action: "send",
      args: nil,
      result: nil,
      duration_us: 0,
      authz: "n/a",
      exception:
        Jason.encode!(%{
          reason: inspect(Map.get(meta, :reason)),
          message_uri: Map.get(meta, :message_uri)
        }),
      inserted_at: DateTime.utc_now()
    }
  end

  # Phase 4-completion Spec 04: persistence telemetry as audit rows so
  # operators see snapshot lifecycle in the same /admin Audit Log stream.
  # Defensive target fallback: build_row must never produce NULL target
  # (NOT NULL constraint on invocations.target).
  defp build_row([:esr, :persistence, phase], measurements, meta)
       when phase in [:restored, :written, :failed] do
    %{
      trace_id: nil,
      caller: nil,
      target: Map.get(meta, :uri) || "snapshot://unknown",
      action: "snapshot.#{phase}",
      args: nil,
      result:
        Jason.encode!(%{
          slices: Map.get(measurements, :slices),
          bytes: Map.get(measurements, :bytes),
          kind_type: Map.get(meta, :kind_type),
          version: Map.get(meta, :version)
        }),
      duration_us: 0,
      authz: "n/a",
      exception:
        if phase == :failed do
          Jason.encode!(%{reason: Map.get(meta, :reason)})
        else
          nil
        end,
      inserted_at: DateTime.utc_now()
    }
  end

  # Phase 4-plus follow-up: CC bridge hook reports persist as audit
  # rows so an operator can grep history beyond the LV in-memory buffer.
  defp build_row([:esr, :cc_bridge, :event], _measurements, meta) do
    %{
      trace_id: nil,
      caller: "cc-bridge://#{Map.get(meta, :bridge_id, "unknown")}",
      target: "cc-bridge://#{Map.get(meta, :bridge_id, "unknown")}/event",
      action: "cc.#{Map.get(meta, :type, "event")}",
      args: nil,
      result: nil,
      duration_us: 0,
      authz: Map.get(meta, :level, "info"),
      exception: Map.get(meta, :text),
      inserted_at: DateTime.utc_now()
    }
  end

  defp serialise_metadata(meta) do
    meta
    |> Enum.map(fn
      {k, %URI{} = u} -> {k, URI.to_string(u)}
      {k, v} when is_atom(v) -> {k, v}
      {k, v} -> {k, v}
    end)
    |> Map.new()
  end

  defp uri_to_str(%URI{} = u), do: URI.to_string(u)
  defp uri_to_str(s) when is_binary(s), do: s
  defp uri_to_str(nil), do: nil
  defp stringify(nil), do: nil
  defp stringify(a) when is_atom(a), do: Atom.to_string(a)
  defp stringify(s) when is_binary(s), do: s
end
