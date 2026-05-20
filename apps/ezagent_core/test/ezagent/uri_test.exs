defmodule Ezagent.URITest do
  use ExUnit.Case, async: true

  describe "parse!/1" do
    test "parses 3-segment entity:// URI (SPEC v3 §3.2)" do
      uri = Ezagent.URI.parse!("entity://user/default/admin")
      assert uri.scheme == "entity"
      assert uri.host == "user"
      assert uri.path == "/default/admin"
    end

    test "parses URI with action query (SPEC v2 §5.2, PR #148)" do
      uri = Ezagent.URI.parse!("entity://agent/default/cc_demo-builder?action=chat.receive")
      assert uri.scheme == "entity"
      assert uri.host == "agent"
      assert uri.path == "/default/cc_demo-builder"
      assert uri.query == "action=chat.receive"
    end

    test "parses cross-workspace entity URI" do
      uri = Ezagent.URI.parse!("entity://agent/team-alpha/cc_demo")
      assert uri.scheme == "entity"
      assert uri.host == "agent"
      assert uri.path == "/team-alpha/cc_demo"
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
        # NOTE: literal `user://default/admin` — the deleted scheme is the point.
        Ezagent.URI.parse!("user" <> "://default/admin")
      end
    end

    test "rejects deleted agent:// scheme" do
      assert_raise ArgumentError, ~r/not registered/, fn ->
        # NOTE: literal `agent://cc/demo` — the deleted scheme is the point.
        Ezagent.URI.parse!("agent" <> "://cc/demo")
      end
    end

    test "rejects 2-segment entity URI (SPEC v3 §3.2)" do
      # NOTE: literal `entity://user/admin` — the rejected 2-seg form is the point.
      legacy = "entity://user/" <> "admin"

      assert_raise ArgumentError, ~r/workspace segment/, fn ->
        Ezagent.URI.parse!(legacy)
      end
    end

    test "rejects 2-segment entity agent URI (SPEC v3 §3.2)" do
      # NOTE: literal `entity://agent/cc_demo` — the rejected 2-seg form is the point.
      legacy = "entity://agent/" <> "cc_demo"

      assert_raise ArgumentError, ~r/workspace segment/, fn ->
        Ezagent.URI.parse!(legacy)
      end
    end

    test "rejects 4+ segment entity URI (sub-resource reserved)" do
      assert_raise ArgumentError, ~r/sub-resource positions are reserved/, fn ->
        Ezagent.URI.parse!("entity://user/default/admin/extra")
      end
    end
  end

  describe "instance/1 — entity:// 3-segment authority (SPEC v3)" do
    test "entity:// strips query (SPEC v2 §5.2 — action lives in query)" do
      uri = Ezagent.URI.parse!("entity://agent/default/echo_default?action=echo.say")
      inst = Ezagent.URI.instance(uri)
      assert inst.scheme == "entity"
      assert inst.host == "agent"
      assert inst.path == "/default/echo_default"
      assert inst.query == nil
      assert URI.to_string(inst) == "entity://agent/default/echo_default"
    end

    test "entity:// already-instance form is unchanged" do
      uri = Ezagent.URI.parse!("entity://agent/default/cc_demo-builder")
      assert Ezagent.URI.instance(uri) == uri
    end

    test "entity://user/default/admin is unchanged" do
      uri = Ezagent.URI.parse!("entity://user/default/admin")
      assert Ezagent.URI.instance(uri) == uri
    end

    test "entity:// agent flavor in name prefix is opaque to parser" do
      # PR #141 SPEC v2 §5.14: <flavor>_<name> is one opaque name string.
      uri = Ezagent.URI.parse!("entity://agent/default/cc_demo-builder?action=chat.receive")
      inst = Ezagent.URI.instance(uri)
      assert URI.to_string(inst) == "entity://agent/default/cc_demo-builder"
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

  describe "entity_workspace_uri/1 (SPEC v3 §3.3)" do
    test "extracts workspace URI from default-workspace user entity" do
      uri = Ezagent.URI.parse!("entity://user/default/admin")
      assert Ezagent.URI.entity_workspace_uri(uri) == URI.new!("workspace://default")
    end

    test "extracts workspace URI from cross-workspace agent entity" do
      uri = Ezagent.URI.parse!("entity://agent/team-alpha/cc_demo")
      assert Ezagent.URI.entity_workspace_uri(uri) == URI.new!("workspace://team-alpha")
    end

    test "extracts workspace URI from entity URI with query string" do
      uri = Ezagent.URI.parse!("entity://user/default/admin?action=identity.list_caps")
      assert Ezagent.URI.entity_workspace_uri(uri) == URI.new!("workspace://default")
    end
  end

  describe "subresource/1" do
    test "entity:// without sub-resource returns empty string" do
      uri = Ezagent.URI.parse!("entity://agent/default/cc_demo-builder")
      assert Ezagent.URI.subresource(uri) == ""
    end

    test "entity:// with just /<workspace>/<name> → empty string" do
      uri = Ezagent.URI.parse!("entity://user/default/admin")
      assert Ezagent.URI.subresource(uri) == ""
    end

    test "URI with no path → empty string" do
      uri = Ezagent.URI.parse!("workspace://default")
      assert Ezagent.URI.subresource(uri) == ""
    end
  end

  describe "behavior_action/1 — query-string action parser (SPEC v2 §5.2, PR #148)" do
    test "extracts {behavior_atom, action_atom} from entity:// ?action=" do
      uri = Ezagent.URI.parse!("entity://agent/default/echo_default?action=echo.say")
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
      uri = Ezagent.URI.parse!("entity://agent/default/echo_default")
      assert {:error, :missing_action} = Ezagent.URI.behavior_action(uri)
    end

    test "returns :missing_action when query lacks action key" do
      uri = Ezagent.URI.parse!("entity://agent/default/echo_default?foo=bar")
      assert {:error, :missing_action} = Ezagent.URI.behavior_action(uri)
    end

    test "returns :missing_action for empty action value" do
      uri = Ezagent.URI.parse!("entity://agent/default/echo_default?action=")
      assert {:error, :missing_action} = Ezagent.URI.behavior_action(uri)
    end

    test "returns :malformed_action when action lacks a dot" do
      uri = Ezagent.URI.parse!("entity://agent/default/echo_default?action=justone")
      assert {:error, :malformed_action} = Ezagent.URI.behavior_action(uri)
    end

    test "returns :malformed_action for empty behavior or action half" do
      uri = Ezagent.URI.parse!("entity://agent/default/echo_default?action=.say")
      assert {:error, :malformed_action} = Ezagent.URI.behavior_action(uri)

      uri = Ezagent.URI.parse!("entity://agent/default/echo_default?action=echo.")
      assert {:error, :malformed_action} = Ezagent.URI.behavior_action(uri)
    end
  end
end
