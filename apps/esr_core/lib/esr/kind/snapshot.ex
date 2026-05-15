defmodule Esr.Kind.Snapshot do
  @moduledoc """
  Persistence skeleton for Kind instance state.

  Per Decision #62: snapshots store `kind_type` (stable atom) not the
  module name, so renaming the module doesn't orphan snapshots. Per
  Decision #59: `:on_change` writes only when slice content actually
  differs (BEAM value equality does the dirty check).

  ## Phase 1 scope

  Echo's persistence is `:ephemeral`, so Phase 1 only needs the API
  in place. `load_or_init/2` returns the in-memory initial slice
  when persistence is `:ephemeral`; `maybe_save/4` is a no-op for
  `:ephemeral` and unchanged-state cases. Phase 3 plugs in the
  SQLite read/write for `:on_change`.

  This module deliberately uses `kind_module.type_name()` (not the
  module atom) as the storage key alongside the URI — Decision #62.
  """

  @doc """
  Load a snapshot for `uri` or return an initial state when there is
  none (or when persistence is `:ephemeral`).

  Returns a `state` map keyed by `behavior.state_slice()`.
  """
  @spec load_or_init(URI.t() | String.t(), module(), map()) :: %{atom() => map()}
  def load_or_init(uri, kind_module, args) do
    case kind_module.persistence() do
      :ephemeral ->
        init_fresh(kind_module, args)

      {:snapshot, _} ->
        uri_str = uri_to_str(uri)
        load_with_fallback(uri_str, kind_module, args)
    end
  end

  # Indirection so the compiler's type inference doesn't flag the
  # `{:ok, _}` branch as unreachable while `fetch_snapshot/1` is a
  # Phase-1 stub that always returns `:error`.
  defp load_with_fallback(uri_str, kind_module, args) do
    with {:ok, state_map} <- fetch_snapshot(uri_str) do
      state_map
    else
      _ -> init_fresh(kind_module, args)
    end
  end

  @doc """
  Persist the new state if persistence policy says so AND the slice
  actually changed (Decision #59). No-op for `:ephemeral` or unchanged.
  """
  @spec maybe_save(URI.t() | String.t(), module(), %{atom() => map()}, %{atom() => map()}) :: :ok
  def maybe_save(_uri, kind_module, old_state, new_state) do
    case kind_module.persistence() do
      :ephemeral ->
        :ok

      {:snapshot, :on_change} ->
        if old_state == new_state do
          :ok
        else
          # Phase 3: persist new_state. Skeleton emits telemetry so the
          # call-site is observable already.
          :telemetry.execute([:esr, :persistence, :save_skipped_phase1], %{}, %{})
          :ok
        end

      {:snapshot, :periodic, _ms} ->
        # Phase 2+ periodic saver.
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

  defp fetch_snapshot(_uri_str) do
    # Phase 3 wires SQLite SELECT here. Phase 1 always misses so we
    # always init_fresh.
    :error
  end

  defp uri_to_str(%URI{} = u), do: URI.to_string(u)
  defp uri_to_str(s) when is_binary(s), do: s
end
