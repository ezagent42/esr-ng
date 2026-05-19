defmodule Ezagent.MessageTest do
  use ExUnit.Case, async: true
  alias Ezagent.Message

  @sender URI.parse("entity://user/admin")
  @body %{text: "hello", attachments: []}

  describe "new/3" do
    test "minimal — sender + body required, others default" do
      msg = Message.new(@sender, @body)

      assert msg.sender == @sender
      assert msg.body == @body
      assert msg.mentions == []
      assert msg.ref == nil
      assert %DateTime{} = msg.inserted_at
      assert String.starts_with?(msg.uri, "message://")
    end

    test "URI auto-gen format is `message://<16 lowercase hex>`" do
      msg = Message.new(@sender, @body)
      assert Regex.match?(~r/^message:\/\/[0-9a-f]{16}$/, msg.uri)
    end

    test "URI auto-gen unique across constructions" do
      uris = for _ <- 1..20, do: Message.new(@sender, @body).uri
      assert length(Enum.uniq(uris)) == 20
    end

    test ":mentions opt fills mentions field" do
      mentions = [URI.parse("entity://agent/test_cc-builder")]
      msg = Message.new(@sender, @body, mentions: mentions)
      assert msg.mentions == mentions
    end

    test ":ref opt fills ref (URI) field" do
      ref = URI.parse("message://deadbeef00000000")
      msg = Message.new(@sender, @body, ref: ref)
      assert msg.ref == ref
    end

    test ":inserted_at opt overrides default DateTime.utc_now" do
      fixed = ~U[2026-01-01 00:00:00Z]
      msg = Message.new(@sender, @body, inserted_at: fixed)
      assert msg.inserted_at == fixed
    end

    test ":uri opt overrides auto-gen (for replay / tests)" do
      msg = Message.new(@sender, @body, uri: "message://test-fixed-uri")
      assert msg.uri == "message://test-fixed-uri"
    end

    test "body without :attachments defaults to empty list" do
      msg = Message.new(@sender, %{text: "no attachments key"})
      assert msg.body.attachments == []
      assert msg.body.text == "no attachments key"
    end

    test "body with :attachments preserves caller-provided list" do
      attachments = [URI.parse("file://abc.pdf")]
      msg = Message.new(@sender, %{text: "with attach", attachments: attachments})
      assert msg.body.attachments == attachments
    end
  end

  describe "Jason.Encoder for %URI{}" do
    test "URI struct serializes to its string form" do
      uri = URI.parse("entity://agent/test_cc-builder")
      assert Jason.encode!(uri) == ~s("entity://agent/test_cc-builder")
    end

    test "URI inside a list (mentions field) serializes as JSON array of strings" do
      uris = [URI.parse("entity://agent/test_cc"), URI.parse("entity://user/admin")]
      assert Jason.encode!(uris) == ~s(["entity://agent/test_cc","entity://user/admin"])
    end
  end

  describe "Jason.Encoder for %Ezagent.Message{}" do
    test "round-trip — encode + decode keeps logical fields" do
      msg = Message.new(@sender, @body, mentions: [URI.parse("entity://agent/test_cc")])
      encoded = Jason.encode!(msg)
      assert is_binary(encoded)
      decoded = Jason.decode!(encoded)

      assert decoded["sender"] == "entity://user/admin"
      assert decoded["mentions"] == ["entity://agent/test_cc"]
      assert decoded["body"]["text"] == "hello"
      assert decoded["body"]["attachments"] == []
      assert is_binary(decoded["inserted_at"])
      assert is_binary(decoded["uri"])
      assert is_nil(decoded["ref"])
      # __struct__ should NOT leak into JSON
      refute Map.has_key?(decoded, "__struct__")
    end
  end
end
