defmodule Ezagent.Entity.MagicLinkTokenTest do
  use EzagentCore.DataCase, async: false

  alias Ezagent.Entity.MagicLinkToken

  test "mint/1 returns a raw token; consume/1 returns the email once" do
    {:ok, raw} = MagicLinkToken.mint("allen@example.com")
    assert is_binary(raw) and byte_size(raw) > 20

    assert {:ok, "allen@example.com"} = MagicLinkToken.consume(raw)
  end

  test "consume/1 is single-use — second call fails" do
    {:ok, raw} = MagicLinkToken.mint("x@example.com")
    assert {:ok, _} = MagicLinkToken.consume(raw)
    assert {:error, :consumed} = MagicLinkToken.consume(raw)
  end

  test "consume/1 rejects an expired token" do
    {:ok, raw} = MagicLinkToken.mint("y@example.com", ttl_seconds: -1)
    assert {:error, :expired} = MagicLinkToken.consume(raw)
  end

  test "consume/1 rejects an unknown / malformed token" do
    assert {:error, :invalid} = MagicLinkToken.consume("not-a-real-token")
  end
end
