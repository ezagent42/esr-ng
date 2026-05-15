defmodule Esr.DLQ do
  @moduledoc """
  Dead-letter queue — bounded FIFO of failed / unroutable invocations.

  Per Decision #35 + #68: DLQ is its own table (not mixed into audit
  log). Zero-match routing, behavior exceptions, idempotency-marker
  collisions, etc. all end up here so they're never silently dropped.

  ## Reason enum

  - `:behavior_exception` — `behavior.invoke/4` raised
  - `:unroutable` — zero matchers / `:no_such_actor`
  - `:no_actor` — `KindRegistry.lookup` returned `:error`
  - `:idempotency_duplicate_marker` — saw a key whose result was lost

  ## Phase 1 scope

  Synchronous `Esr.Repo.insert/2` + telemetry emit. Bounded eviction
  (oldest-first) lands in Phase 2 with `Esr.DLQ.Sweeper`. Phase 1's
  DLQ writes are low-volume (only invocation-level failures, no chat),
  so the unbounded-table risk is acceptable in the short term.
  """

  @reasons [:behavior_exception, :unroutable, :no_actor, :idempotency_duplicate_marker]

  @doc """
  Append a row to the DLQ. `payload` is the original invocation (or
  whatever context lets a human debug what was dropped) — JSON-encoded
  by ecto_sqlite3 via the `:map` column type.
  """
  @spec put(atom(), term()) :: :ok
  def put(reason, payload) when reason in @reasons do
    # ecto_sqlite3 with `Repo.insert_all/2` against a string table name
    # doesn't auto-encode `:map` columns — JSON-encode manually so SQLite
    # gets a TEXT value. Schemaful inserts (Phase 2+ with Ecto.Schema)
    # would handle this automatically.
    row = %{
      reason: Atom.to_string(reason),
      payload: Jason.encode!(payload_to_map(payload)),
      inserted_at: DateTime.utc_now()
    }

    {1, _} = EsrCore.Repo.insert_all("dlq", [row])

    :telemetry.execute([:esr, :dlq, :write], %{}, %{reason: reason})
    :ok
  end

  @doc "List of valid reason atoms."
  def reasons, do: @reasons

  defp payload_to_map(%Esr.Invocation{} = inv) do
    %{
      target: URI.to_string(inv.target),
      mode: Atom.to_string(inv.mode),
      args: inv.args,
      caller: caller_string(inv.ctx)
    }
  end

  defp payload_to_map(map) when is_map(map), do: map
  defp payload_to_map(other), do: %{inspect: inspect(other)}

  defp caller_string(%{caller: %URI{} = u}), do: URI.to_string(u)
  defp caller_string(%{caller: s}) when is_binary(s), do: s
  defp caller_string(_), do: nil
end
