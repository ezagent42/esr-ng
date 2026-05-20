defmodule EzagentWeb.RateLimiter do
  @moduledoc """
  Username & Auth M3 — minimal fixed-window rate limiter.

  ETS-backed, no extra dependency. Used to throttle the unauthenticated
  `POST /login` email-send path (per-email + per-IP) so it can't be
  abused for email bombing or SMTP-quota exhaustion.

  Fixed-window semantics: each key gets a counter that resets when its
  window elapses. Coarse but sufficient for an abuse backstop.

  The ETS table is created by `init_table/0`, called from
  `EzagentWeb.Application`.
  """

  @table :ezagent_rate_limiter

  @doc "Create the ETS table. Idempotent. Call once at app boot."
  @spec init_table() :: :ok
  def init_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set, {:write_concurrency, true}])
    end

    :ok
  end

  @doc """
  Check + record one hit for `key`. Returns `:ok` if under the limit,
  `{:error, :rate_limited}` otherwise.

  Opts: `:limit` (max hits per window), `:window_ms`.
  """
  @spec check(String.t(), keyword()) :: :ok | {:error, :rate_limited}
  def check(key, opts) when is_binary(key) do
    limit = Keyword.fetch!(opts, :limit)
    window_ms = Keyword.fetch!(opts, :window_ms)
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{^key, count, window_start}] when now - window_start < window_ms ->
        if count >= limit do
          {:error, :rate_limited}
        else
          :ets.insert(@table, {key, count + 1, window_start})
          :ok
        end

      _ ->
        # No record, or the window elapsed → start a fresh window.
        :ets.insert(@table, {key, 1, now})
        :ok
    end
  end

  @doc "Clear every counter. Test-support."
  @spec reset_all() :: :ok
  def reset_all do
    init_table()
    :ets.delete_all_objects(@table)
    :ok
  end
end
