defmodule EzagentWeb.RateLimiterTest do
  use ExUnit.Case, async: false

  alias EzagentWeb.RateLimiter

  setup do
    RateLimiter.reset_all()
    :ok
  end

  test "allows up to the limit then blocks within the window" do
    assert RateLimiter.check("k1", limit: 2, window_ms: 60_000) == :ok
    assert RateLimiter.check("k1", limit: 2, window_ms: 60_000) == :ok
    assert RateLimiter.check("k1", limit: 2, window_ms: 60_000) == {:error, :rate_limited}
  end

  test "separate keys have independent counters" do
    assert RateLimiter.check("a", limit: 1, window_ms: 60_000) == :ok
    assert RateLimiter.check("b", limit: 1, window_ms: 60_000) == :ok
  end

  test "the counter resets after the window elapses" do
    assert RateLimiter.check("w", limit: 1, window_ms: 30) == :ok
    assert RateLimiter.check("w", limit: 1, window_ms: 30) == {:error, :rate_limited}
    Process.sleep(40)
    assert RateLimiter.check("w", limit: 1, window_ms: 30) == :ok
  end
end
