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

  @events [
    [:esr, :invoke, :stop],
    [:esr, :invoke, :error]
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
      authz: "stub_grant",
      exception: nil,
      inserted_at: DateTime.utc_now()
    }
  end

  defp build_row([:esr, :invoke, :error], %{duration_us: us}, meta) do
    %{
      trace_id: nil,
      caller: uri_to_str(Map.get(meta, :caller)),
      target: uri_to_str(Map.get(meta, :target)),
      action: nil,
      args: nil,
      result: nil,
      duration_us: us,
      authz: "stub_grant",
      # JSON-encode for ecto_sqlite3 schemaless insert_all (see Esr.DLQ).
      exception: Jason.encode!(%{reason: inspect(Map.get(meta, :reason))}),
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
