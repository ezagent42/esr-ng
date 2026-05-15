defmodule Esr.ReadyGate do
  @moduledoc """
  ReadyGate — ETS-backed three-state map per Kind instance URI.

  States: `:unknown` (default for unseen URIs), `:not_ready` (registered
  but not yet announced ready — see `Esr.Kind.Server` init), `:ready`
  (announced).

  Used by `Esr.Invocation.dispatch/1` to decide:
  - `:not_ready` + `:cast` → buffer to `Esr.PendingDelivery`
  - `:not_ready` + `:call` → fail-fast (hard invariant #3)
  - `:ready` → proceed to GenServer.call/cast

  Owned by `EsrCore.EtsOwner` (single shared GenServer per
  DECISIONS implementation-decision §ETS table owner — Option B).
  """

  @table :esr_ready_gate

  @type status :: :unknown | :not_ready | :ready

  @doc "ETS table name — for `EsrCore.EtsOwner` to create at boot."
  def table, do: @table

  @doc """
  Current status of a URI. Returns `:unknown` if no entry exists.

  Accepts a `%URI{}` or its string form; both normalise to the string key.
  """
  @spec status(URI.t() | String.t()) :: status()
  def status(uri) do
    case :ets.lookup(@table, key(uri)) do
      [{_, s}] -> s
      [] -> :unknown
    end
  end

  @doc "Set a URI's status. Idempotent."
  @spec put(URI.t() | String.t(), status()) :: :ok
  def put(uri, status) when status in [:unknown, :not_ready, :ready] do
    :ets.insert(@table, {key(uri), status})
    :ok
  end

  @doc "Convenience for `put(uri, :ready)`."
  @spec mark_ready(URI.t() | String.t()) :: :ok
  def mark_ready(uri), do: put(uri, :ready)

  defp key(%URI{} = uri), do: URI.to_string(uri)
  defp key(uri) when is_binary(uri), do: uri
end
