defmodule Ezagent.Kind.Snapshot do
  @moduledoc """
  Per-Kind state persistence (Phase 4-completion Spec 04).

  Each Kind declares `persistence/0` from one of:
  - `:ephemeral` — no persistence (default for most Kinds)
  - `{:snapshot, :on_change}` — sync write after every dispatch where
    `new_slice != old_slice` (Decision #59); restore on boot
  - `{:snapshot, :periodic, ms}` — async write every `ms` via
    `Ezagent.Snapshot.Writer`; restore on boot
  - `:on_terminate` — write on `GenServer.terminate/2`; restore on boot
  - `:external` — slice state lives in a foreign system; this module
    does NOT touch the DB; plugin author's `init_slice/1` reads from
    the foreign system

  Per Decision #62: snapshots key by `kind_type` (stable atom) — module
  rename doesn't orphan rows. Per Decision #59: `:on_change` writes
  only when the slice content actually differs (BEAM value equality).

  ## Sync vs async (Q2)

  Per Spec 04 Q2 default: `:on_change` is **sync** (~1ms SQLite local;
  zero loss within process lifetime); `:periodic` is **async** via
  `Ezagent.Snapshot.Writer` (mirrors `Ezagent.Audit.Writer` pattern from
  Decision #60).

  ## Failure mode (Q3)

  Write failure does NOT crash the Kind. Log + `[:ezagent, :persistence,
  :failed]` telemetry; the in-memory slice is the truth until next
  write succeeds. `feedback_let_it_crash_no_workarounds` applies to
  invariant violations, not external resource exhaustion (disk full).

  ## Restore safety

  `:erlang.binary_to_term/2` is called with `[:safe]` flag — rejects
  atoms not already loaded in the runtime (security against
  snapshot-table-write-then-bootstrap-arbitrary-atom attacks).
  """

  require Logger
  alias Ezagent.Ecto.KindSnapshot

  @doc """
  Load a snapshot for `uri` or return an initial state. Persistence
  policy determines whether DB is touched.

  Returns a state map keyed by `behavior.state_slice()`.
  """
  @spec load_or_init(URI.t() | String.t(), module(), map()) :: %{atom() => map()}
  def load_or_init(uri, kind_module, args) do
    case kind_module.persistence() do
      :ephemeral ->
        init_fresh(kind_module, args)

      :external ->
        # Plugin author's init_slice/1 reads from foreign system; don't touch DB.
        init_fresh(kind_module, args)

      :on_terminate ->
        load_with_fallback(uri, kind_module, args)

      {:snapshot, _strategy} ->
        load_with_fallback(uri, kind_module, args)
    end
  end

  defp load_with_fallback(uri, kind_module, args) do
    uri_str = uri_to_str(uri)
    fresh = init_fresh(kind_module, args)

    case fetch_snapshot(uri_str, kind_module) do
      {:ok, loaded_state} ->
        emit_restored(uri_str, loaded_state)
        # Merge so newly-added Behaviors get fresh init values (Q5).
        Map.merge(fresh, loaded_state)

      :error ->
        fresh

      {:error, reason} ->
        Logger.warning(
          "Ezagent.Kind.Snapshot: load failed for #{uri_str}: #{inspect(reason)}; using fresh init"
        )

        fresh
    end
  end

  defp fetch_snapshot(uri_str, kind_module) do
    case KindSnapshot.get(uri_str) do
      nil ->
        :error

      row ->
        with :ok <- check_version(row, kind_module),
             {:ok, state} <- KindSnapshot.decode_state(row) do
          {:ok, state}
        end
    end
  end

  defp check_version(row, kind_module) do
    declared = snapshot_version_of(kind_module)
    stored = row.version || 0

    cond do
      stored == declared ->
        :ok

      stored < declared ->
        # Phase 4 v1: per Spec 04 §2.G, accept fail-loud. Future Phase 5
        # can call Behavior.upgrade_slice/3 here.
        {:error, {:snapshot_version_too_old, stored, declared}}

      stored > declared ->
        # Newer snapshot vs older code = corruption risk; refuse.
        {:error, {:snapshot_version_too_new, stored, declared}}
    end
  end

  defp snapshot_version_of(kind_module) do
    if function_exported?(kind_module, :snapshot_version, 0) do
      kind_module.snapshot_version()
    else
      0
    end
  end

  @doc """
  Persist the new state per policy. No-op for `:ephemeral` / `:external`
  / unchanged slice.

  Returns `:ok` even on write failure (logged + telemetry); the caller
  (Kind.Server) treats the in-memory slice as the truth.
  """
  @spec maybe_save(URI.t() | String.t(), module(), %{atom() => map()}, %{atom() => map()}) :: :ok
  def maybe_save(uri, kind_module, old_state, new_state) do
    case kind_module.persistence() do
      :ephemeral ->
        :ok

      :external ->
        :ok

      :on_terminate ->
        # Only written via save_now/3 in terminate; not in dispatch hot path.
        :ok

      {:snapshot, :on_change} ->
        if old_state == new_state do
          :ok
        else
          save_now(uri, kind_module, new_state)
        end

      {:snapshot, :periodic, _ms} ->
        # Async via Writer. Timer in Server fires save_now via Writer cast.
        # maybe_save itself is a no-op for periodic (only the timer writes).
        :ok
    end
  end

  @doc """
  Synchronous write — used by `:on_change`, `:on_terminate`, and the
  Writer's flush path. Logs + emits `:failed` telemetry on error.
  """
  @spec save_now(URI.t() | String.t(), module(), %{atom() => map()}) :: :ok
  def save_now(uri, kind_module, state) do
    uri_str = uri_to_str(uri)
    kind_type_str = Atom.to_string(kind_module.type_name())
    version = snapshot_version_of(kind_module)
    binary = :erlang.term_to_binary(state)

    case KindSnapshot.upsert(uri_str, kind_type_str, binary, version) do
      {:ok, _row} ->
        :telemetry.execute(
          [:ezagent, :persistence, :written],
          %{bytes: byte_size(binary)},
          %{uri: uri_str, kind_type: kind_type_str, version: version}
        )

        :ok

      {:error, reason} = err ->
        Logger.warning("Ezagent.Kind.Snapshot: save failed for #{uri_str}: #{inspect(reason)}")

        :telemetry.execute(
          [:ezagent, :persistence, :failed],
          %{},
          %{uri: uri_str, kind_type: kind_type_str, reason: inspect(reason)}
        )

        _ = err
        :ok
    end
  end

  # ---------------------------------------------------------------------
  # Internals

  defp init_fresh(kind_module, args) do
    kind_module.behaviors()
    |> Enum.map(fn behavior ->
      {behavior.state_slice(), behavior.init_slice(args)}
    end)
    |> Map.new()
  end

  defp emit_restored(uri_str, state) do
    :telemetry.execute(
      [:ezagent, :persistence, :restored],
      %{slices: map_size(state)},
      %{uri: uri_str}
    )
  end

  defp uri_to_str(%URI{} = u), do: URI.to_string(u)
  defp uri_to_str(s) when is_binary(s), do: s
end
