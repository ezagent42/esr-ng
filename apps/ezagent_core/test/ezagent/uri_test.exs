defmodule Ezagent.URITest do
  use ExUnit.Case, async: true

  describe "parse!/1" do
    test "parses entity:// URI" do
      uri = Ezagent.URI.parse!("entity://user/admin")
      assert uri.scheme == "entity"
      assert uri.host == "user"
      assert uri.path == "/admin"
    end

    test "parses URI with behavior path" do
      uri = Ezagent.URI.parse!("entity://agent/cc_demo-builder/behavior/chat/receive")
      assert uri.scheme == "entity"
      assert uri.host == "agent"
      assert uri.path == "/cc_demo-builder/behavior/chat/receive"
    end

    test "parses legacy 1-seg session:// URI (kept alive until PR #146)" do
      uri = Ezagent.URI.parse!("session://main")
      assert uri.scheme == "session"
      assert uri.host == "main"
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

    test "rejects deleted user:// scheme" do
      assert_raise ArgumentError, ~r/not in known set/, fn ->
        # NOTE: literal `user://admin` — the deleted scheme is the point.
        Ezagent.URI.parse!("user" <> "://admin")
      end
    end

    test "rejects deleted agent:// scheme" do
      assert_raise ArgumentError, ~r/not in known set/, fn ->
        # NOTE: literal `agent://cc/demo` — the deleted scheme is the point.
        Ezagent.URI.parse!("agent" <> "://cc/demo")
      end
    end
  end

  describe "instance/1 — entity:// uniform 2-segment split" do
    test "entity:// keeps host + name as instance, strips sub-resource" do
      uri = Ezagent.URI.parse!("entity://agent/echo_default/behavior/echo/say")
      inst = Ezagent.URI.instance(uri)
      assert inst.scheme == "entity"
      assert inst.host == "agent"
      assert inst.path == "/echo_default"
      assert URI.to_string(inst) == "entity://agent/echo_default"
    end

    test "entity:// already-instance form is unchanged" do
      uri = Ezagent.URI.parse!("entity://agent/cc_demo-builder")
      assert Ezagent.URI.instance(uri) == uri
    end

    test "entity://user/X is unchanged (no sub-resource)" do
      uri = Ezagent.URI.parse!("entity://user/admin")
      assert Ezagent.URI.instance(uri) == uri
    end

    test "entity:// agent flavor in name prefix is opaque to parser" do
      # PR #141 SPEC v2 §5.14: <flavor>_<name> is one opaque name string.
      uri = Ezagent.URI.parse!("entity://agent/cc_demo-builder/behavior/chat/receive")
      inst = Ezagent.URI.instance(uri)
      assert URI.to_string(inst) == "entity://agent/cc_demo-builder"
    end

    test "decoupled from /behavior/ keyword — hypothetical sub-resource still splits cleanly" do
      uri = Ezagent.URI.parse!("entity://agent/cc_demo-builder/auth/login")
      inst = Ezagent.URI.instance(uri)
      assert URI.to_string(inst) == "entity://agent/cc_demo-builder"
    end
  end

  describe "instance/1 — legacy 1-seg schemes (pre-#146 transitional)" do
    test "legacy 1-seg session:// drops entire path" do
      uri = Ezagent.URI.parse!("session://main/behavior/chat/send")
      inst = Ezagent.URI.instance(uri)
      assert inst.scheme == "session"
      assert inst.host == "main"
      assert inst.path == nil
      assert URI.to_string(inst) == "session://main"
    end

    test "instance of already-instance legacy URI is itself" do
      uri = Ezagent.URI.parse!("workspace://default")
      assert Ezagent.URI.instance(uri) == uri
    end
  end

  describe "subresource/1" do
    test "entity:// returns segments after the name" do
      uri = Ezagent.URI.parse!("entity://agent/cc_demo-builder/behavior/chat/receive")
      assert Ezagent.URI.subresource(uri) == "behavior/chat/receive"
    end

    test "entity:// without sub-resource returns empty string" do
      uri = Ezagent.URI.parse!("entity://agent/cc_demo-builder")
      assert Ezagent.URI.subresource(uri) == ""
    end

    test "legacy 1-seg session:// returns entire path" do
      uri = Ezagent.URI.parse!("session://main/behavior/chat/send")
      assert Ezagent.URI.subresource(uri) == "behavior/chat/send"
    end

    test "entity:// with just /<name> → empty string" do
      uri = Ezagent.URI.parse!("entity://user/admin")
      assert Ezagent.URI.subresource(uri) == ""
    end

    test "URI with no path → empty string" do
      uri = Ezagent.URI.parse!("workspace://default")
      assert Ezagent.URI.subresource(uri) == ""
    end

    test "entity:// with hypothetical /auth/ sub-resource" do
      uri = Ezagent.URI.parse!("entity://agent/cc_demo-builder/auth/login")
      assert Ezagent.URI.subresource(uri) == "auth/login"
    end
  end

  describe "behavior_action/1 — named parser" do
    test "extracts {behavior_atom, action_atom} from entity:// path-style" do
      uri = Ezagent.URI.parse!("entity://agent/echo_default/behavior/echo/say")
      assert {:ok, {:echo, :say}} = Ezagent.URI.behavior_action(uri)
    end

    test "extracts from legacy 1-seg session:// scheme" do
      uri = Ezagent.URI.parse!("session://main/behavior/chat/send")
      assert {:ok, {:chat, :send}} = Ezagent.URI.behavior_action(uri)
    end

    test "returns :malformed_path for URI without sub-resource" do
      uri = Ezagent.URI.parse!("entity://agent/echo_default")
      assert {:error, :malformed_path} = Ezagent.URI.behavior_action(uri)
    end

    test "returns :malformed_path for non-behavior sub-resource" do
      uri = Ezagent.URI.parse!("entity://agent/cc_demo-builder/auth/login")
      assert {:error, :malformed_path} = Ezagent.URI.behavior_action(uri)
    end

    test "returns :malformed_path when behavior path is incomplete" do
      uri = Ezagent.URI.parse!("entity://agent/echo_default/behavior/just-one")
      assert {:error, :malformed_path} = Ezagent.URI.behavior_action(uri)
    end
  end
end
