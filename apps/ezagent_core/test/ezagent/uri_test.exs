defmodule Ezagent.URITest do
  use ExUnit.Case, async: true

  describe "parse!/1" do
    test "parses agent:// URI" do
      uri = Ezagent.URI.parse!("agent://allen-builder")
      assert uri.scheme == "agent"
      assert uri.host == "allen-builder"
    end

    test "parses URI with behavior path" do
      uri = Ezagent.URI.parse!("agent://echo/default/behavior/echo/say")
      assert uri.scheme == "agent"
      assert uri.host == "echo"
      assert uri.path == "/default/behavior/echo/say"
    end

    test "raises on missing scheme" do
      assert_raise ArgumentError, ~r/missing scheme/, fn ->
        Ezagent.URI.parse!("/no-scheme")
      end
    end

    test "raises on unknown scheme" do
      assert_raise ArgumentError, ~r/not in known set/, fn ->
        Ezagent.URI.parse!("http://example.com")
      end
    end
  end

  describe "instance/1 — positional split" do
    test "agent:// keeps type + name as instance, strips sub-resource" do
      uri = Ezagent.URI.parse!("agent://echo/default/behavior/echo/say")
      inst = Ezagent.URI.instance(uri)
      assert inst.scheme == "agent"
      assert inst.host == "echo"
      assert inst.path == "/default"
      assert URI.to_string(inst) == "agent://echo/default"
    end

    test "agent:// already-instance form is unchanged (still has /name)" do
      uri = Ezagent.URI.parse!("agent://cc/demo-builder")
      assert Ezagent.URI.instance(uri) == uri
    end

    test "non-agent scheme drops entire path" do
      uri = Ezagent.URI.parse!("session://main/behavior/chat/send")
      inst = Ezagent.URI.instance(uri)
      assert inst.scheme == "session"
      assert inst.host == "main"
      assert inst.path == nil
      assert URI.to_string(inst) == "session://main"
    end

    test "instance of an already-instance non-agent URI is itself" do
      uri = Ezagent.URI.parse!("user://admin")
      assert Ezagent.URI.instance(uri) == uri
    end

    test "decoupled from /behavior/ keyword — hypothetical sub-resource still splits cleanly" do
      # PR-A: instance/1 is positional, NOT keyword-based. A future
      # `/auth/...` sub-resource (or any other) is treated identically.
      uri = Ezagent.URI.parse!("agent://cc/demo-builder/auth/login")
      inst = Ezagent.URI.instance(uri)
      assert URI.to_string(inst) == "agent://cc/demo-builder"
    end
  end

  describe "subresource/1" do
    test "agent:// returns segments after the name" do
      uri = Ezagent.URI.parse!("agent://cc/demo-builder/behavior/chat/receive")
      assert Ezagent.URI.subresource(uri) == "behavior/chat/receive"
    end

    test "agent:// without sub-resource returns empty string" do
      uri = Ezagent.URI.parse!("agent://cc/demo-builder")
      assert Ezagent.URI.subresource(uri) == ""
    end

    test "non-agent scheme returns entire path" do
      uri = Ezagent.URI.parse!("session://main/behavior/chat/send")
      assert Ezagent.URI.subresource(uri) == "behavior/chat/send"
    end

    test "no path → empty string" do
      uri = Ezagent.URI.parse!("user://admin")
      assert Ezagent.URI.subresource(uri) == ""
    end

    test "agent:// with hypothetical /auth/ sub-resource" do
      uri = Ezagent.URI.parse!("agent://cc/demo-builder/auth/login")
      assert Ezagent.URI.subresource(uri) == "auth/login"
    end
  end

  describe "behavior_action/1 — named parser" do
    test "extracts {behavior_atom, action_atom} from agent:// path-style" do
      uri = Ezagent.URI.parse!("agent://echo/default/behavior/echo/say")
      assert {:ok, {:echo, :say}} = Ezagent.URI.behavior_action(uri)
    end

    test "extracts from non-agent scheme" do
      uri = Ezagent.URI.parse!("session://main/behavior/chat/send")
      assert {:ok, {:chat, :send}} = Ezagent.URI.behavior_action(uri)
    end

    test "returns :malformed_path for URI without sub-resource" do
      uri = Ezagent.URI.parse!("agent://echo")
      assert {:error, :malformed_path} = Ezagent.URI.behavior_action(uri)
    end

    test "returns :malformed_path for non-behavior sub-resource" do
      # PR-A: behavior_action is a NAMED parser — only matches the
      # `behavior/` keyword in the sub-resource. Future `/auth/...`
      # would be parsed by a separate `auth_action/1`.
      uri = Ezagent.URI.parse!("agent://cc/demo-builder/auth/login")
      assert {:error, :malformed_path} = Ezagent.URI.behavior_action(uri)
    end

    test "returns :malformed_path when behavior path is incomplete" do
      uri = Ezagent.URI.parse!("agent://echo/default/behavior/just-one")
      assert {:error, :malformed_path} = Ezagent.URI.behavior_action(uri)
    end
  end
end
