defmodule Ezagent.URITest do
  use ExUnit.Case, async: true

  describe "parse!/1" do
    test "parses entity:// URI" do
      uri = Ezagent.URI.parse!("entity://user/admin")
      assert uri.scheme == "entity"
      assert uri.host == "user"
      assert uri.path == "/admin"
    end

    test "parses URI with action query (SPEC v2 §5.2, PR #148)" do
      uri = Ezagent.URI.parse!("entity://agent/cc_demo-builder?action=chat.receive")
      assert uri.scheme == "entity"
      assert uri.host == "agent"
      assert uri.path == "/cc_demo-builder"
      assert uri.query == "action=chat.receive"
    end

    test "parses legacy 1-seg session:// URI (kept alive until later PR)" do
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
      assert_raise ArgumentError, ~r/not registered/, fn ->
        Ezagent.URI.parse!("http://example.com")
      end
    end

    test "rejects deleted user:// scheme" do
      assert_raise ArgumentError, ~r/not registered/, fn ->
        # NOTE: literal `user://admin` — the deleted scheme is the point.
        Ezagent.URI.parse!("user" <> "://admin")
      end
    end

    test "rejects deleted agent:// scheme" do
      assert_raise ArgumentError, ~r/not registered/, fn ->
        # NOTE: literal `agent://cc/demo` — the deleted scheme is the point.
        Ezagent.URI.parse!("agent" <> "://cc/demo")
      end
    end
  end

  describe "instance/1 — entity:// uniform 2-segment split" do
    test "entity:// strips query (SPEC v2 §5.2 — action lives in query)" do
      uri = Ezagent.URI.parse!("entity://agent/echo_default?action=echo.say")
      inst = Ezagent.URI.instance(uri)
      assert inst.scheme == "entity"
      assert inst.host == "agent"
      assert inst.path == "/echo_default"
      assert inst.query == nil
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
      uri = Ezagent.URI.parse!("entity://agent/cc_demo-builder?action=chat.receive")
      inst = Ezagent.URI.instance(uri)
      assert URI.to_string(inst) == "entity://agent/cc_demo-builder"
    end

    test "entity:// trailing path sub-resource (hypothetical /auth/login) is stripped" do
      uri = Ezagent.URI.parse!("entity://agent/cc_demo-builder/auth/login")
      inst = Ezagent.URI.instance(uri)
      assert URI.to_string(inst) == "entity://agent/cc_demo-builder"
    end
  end

  describe "instance/1 — legacy 1-seg schemes (pre-uniform-2seg transitional)" do
    test "legacy 1-seg session:// strips query" do
      uri = Ezagent.URI.parse!("session://main?action=chat.send")
      inst = Ezagent.URI.instance(uri)
      assert inst.scheme == "session"
      assert inst.host == "main"
      assert inst.path == nil
      assert inst.query == nil
      assert URI.to_string(inst) == "session://main"
    end

    test "instance of already-instance legacy URI is itself" do
      uri = Ezagent.URI.parse!("workspace://default")
      assert Ezagent.URI.instance(uri) == uri
    end
  end

  describe "subresource/1" do
    test "entity:// returns segments after the name (rare under SPEC v2 §5.2)" do
      # Under SPEC v2 §5.2 actions live in query, so /behavior/... path is gone.
      # subresource/1 still works for hypothetical future named sub-resources
      # (e.g. /auth/login). Test uses /auth/ to keep the parser exercised.
      uri = Ezagent.URI.parse!("entity://agent/cc_demo-builder/auth/login")
      assert Ezagent.URI.subresource(uri) == "auth/login"
    end

    test "entity:// without sub-resource returns empty string" do
      uri = Ezagent.URI.parse!("entity://agent/cc_demo-builder")
      assert Ezagent.URI.subresource(uri) == ""
    end

    test "entity:// with just /<name> → empty string" do
      uri = Ezagent.URI.parse!("entity://user/admin")
      assert Ezagent.URI.subresource(uri) == ""
    end

    test "URI with no path → empty string" do
      uri = Ezagent.URI.parse!("workspace://default")
      assert Ezagent.URI.subresource(uri) == ""
    end
  end

  describe "behavior_action/1 — query-string action parser (SPEC v2 §5.2, PR #148)" do
    test "extracts {behavior_atom, action_atom} from entity:// ?action=" do
      uri = Ezagent.URI.parse!("entity://agent/echo_default?action=echo.say")
      assert {:ok, {:echo, :say}} = Ezagent.URI.behavior_action(uri)
    end

    test "extracts from legacy 1-seg session:// scheme" do
      uri = Ezagent.URI.parse!("session://main?action=chat.send")
      assert {:ok, {:chat, :send}} = Ezagent.URI.behavior_action(uri)
    end

    test "extracts when behavior or action contains underscores" do
      uri = Ezagent.URI.parse!("workspace://default/main?action=routing.add_rule")
      assert {:ok, {:routing, :add_rule}} = Ezagent.URI.behavior_action(uri)
    end

    test "returns :missing_action for URI without query" do
      uri = Ezagent.URI.parse!("entity://agent/echo_default")
      assert {:error, :missing_action} = Ezagent.URI.behavior_action(uri)
    end

    test "returns :missing_action when query lacks action key" do
      uri = Ezagent.URI.parse!("entity://agent/echo_default?foo=bar")
      assert {:error, :missing_action} = Ezagent.URI.behavior_action(uri)
    end

    test "returns :missing_action for empty action value" do
      uri = Ezagent.URI.parse!("entity://agent/echo_default?action=")
      assert {:error, :missing_action} = Ezagent.URI.behavior_action(uri)
    end

    test "returns :malformed_action when action lacks a dot" do
      uri = Ezagent.URI.parse!("entity://agent/echo_default?action=justone")
      assert {:error, :malformed_action} = Ezagent.URI.behavior_action(uri)
    end

    test "returns :malformed_action for empty behavior or action half" do
      uri = Ezagent.URI.parse!("entity://agent/echo_default?action=.say")
      assert {:error, :malformed_action} = Ezagent.URI.behavior_action(uri)

      uri = Ezagent.URI.parse!("entity://agent/echo_default?action=echo.")
      assert {:error, :malformed_action} = Ezagent.URI.behavior_action(uri)
    end
  end
end
