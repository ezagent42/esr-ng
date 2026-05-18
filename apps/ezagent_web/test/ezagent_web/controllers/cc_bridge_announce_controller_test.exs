defmodule EzagentWeb.CcBridgeAnnounceControllerTest do
  use ExUnit.Case
  import Phoenix.ConnTest

  @endpoint EzagentWeb.Endpoint

  setup do
    Phoenix.PubSub.subscribe(EzagentCore.PubSub, Ezagent.Bridge.V1Prototype.Server.topic())
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  test "POST /api/cc-bridge/announce registers bridge + broadcasts", %{conn: conn} do
    body = %{
      "bridge_id" => "ctrl-test-#{System.unique_integer([:positive])}",
      "claude_info" => %{"name" => "claude", "version" => "1.0"},
      "tools" => ["esr_announce"]
    }

    conn = post(conn, "/api/cc-bridge/announce", body)

    assert %{"ok" => true, "bridge_id" => bid} = json_response(conn, 200)
    assert bid == body["bridge_id"]

    assert_receive {:cc_connected, ^bid, _entry}, 500
  end

  test "POST without bridge_id generates a fallback id", %{conn: conn} do
    body = %{"claude_info" => %{"name" => "anon"}}
    conn = post(conn, "/api/cc-bridge/announce", body)

    assert %{"ok" => true, "bridge_id" => bid} = json_response(conn, 200)
    assert String.starts_with?(bid, "bridge-")
  end
end
