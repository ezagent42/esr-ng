defmodule EsrWeb.CcBridgeAnnounceControllerPhase2Test do
  @moduledoc """
  Phase 2c-step 1 + Phase 3b-step 2 contract change tests.

  **Phase 3 contract change (per P3-D9 + #P1-6)**: bridge announce no
  longer auto-joins session://main. Agent is floating until admin
  explicitly dispatches chat/join via LV or another path.

  Verifies (Phase 3 updated):
  1. POST /announce with agent_uri spawns Agent Kind, binds to
     bridge_id, but does NOT auto-join any session (floating)
  2. POST /reply with bound agent + after manual join → forwards via
     Agent's chat/send dispatch (now requires explicit pre-join)
  3. POST /reply with bridge that has no agent returns 422
  4. POST /disconnect terminates Agent Kind + unbinds
  """

  use ExUnit.Case
  import Phoenix.ConnTest

  alias Esr.Behavior.Chat
  alias Esr.Bridge.V1Prototype.Server, as: BridgeServer
  alias Esr.{KindRegistry, Message, MessageStore}
  alias Esr.Entity.{Session, User}

  @endpoint EsrWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(EsrCore.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(EsrCore.Repo, {:shared, self()})

    conn = Phoenix.ConnTest.build_conn()
    {:ok, conn: conn}
  end

  describe "announce with agent_uri (Phase 3 floating)" do
    test "spawns Agent Kind, binds to bridge_id, but does NOT auto-join session", %{conn: conn} do
      bridge_id = "p3-announce-#{System.unique_integer([:positive])}"
      agent_uri_str = "agent://cc-builder-#{System.unique_integer([:positive])}"

      conn =
        post(conn, "/api/cc-bridge/announce", %{
          "bridge_id" => bridge_id,
          "agent_uri" => agent_uri_str,
          "claude_info" => %{"name" => "claude"}
        })

      assert %{"ok" => true, "bridge_id" => ^bridge_id} = json_response(conn, 200)

      # Agent Kind in KindRegistry
      agent_uri = URI.new!(agent_uri_str)
      assert {:ok, agent_pid} = KindRegistry.lookup(agent_uri)
      assert Process.alive?(agent_pid)

      # Server has the binding
      assert {:ok, ^bridge_id} = BridgeServer.bridge_for_agent(agent_uri)

      # Phase 3 contract change: NOT in session://main members (floating)
      {:ok, session_pid} = KindRegistry.lookup(Session.default_uri())
      %{state: %{chat: s}} = :sys.get_state(session_pid)
      refute Map.has_key?(s.members, agent_uri), "agent should be floating, not in main"

      # Cleanup
      delete(conn, "/api/cc-bridge/announce/#{bridge_id}")
    end
  end

  describe "reply with bound agent (Phase 3: requires manual join first)" do
    test "after manual join, forwards text → Agent dispatches chat/send → admin user:events receives",
         %{conn: conn} do
      bridge_id = "p3-reply-#{System.unique_integer([:positive])}"
      agent_uri_str = "agent://cc-replier-#{System.unique_integer([:positive])}"

      post(conn, "/api/cc-bridge/announce", %{
        "bridge_id" => bridge_id,
        "agent_uri" => agent_uri_str
      })

      # Phase 3: manually join agent to main (LV would do this in real
      # flow; we simulate it directly via dispatch)
      agent_uri = URI.new!(agent_uri_str)
      session_uri = Session.default_uri()

      :ok =
        Esr.Invocation.dispatch(%Esr.Invocation{
          target: URI.new!("#{URI.to_string(session_uri)}/behavior/chat/join"),
          mode: :cast,
          args: %{member: agent_uri},
          ctx: %{caller: agent_uri, caps: User.admin_caps(), reply: :ignore}
        })

      {:ok, session_pid} = KindRegistry.lookup(session_uri)

      assert wait_until(fn ->
               %{state: %{chat: s}} = :sys.get_state(session_pid)
               Map.has_key?(s.members, agent_uri)
             end)

      # Subscribe to admin user:events — when agent replies, it dispatches
      # chat/send which fans out :receive to admin (who's already joined).
      :ok = Phoenix.PubSub.subscribe(EsrCore.PubSub, Chat.user_events_topic(User.admin_uri()))

      # Trigger the reply path
      reply_text = "hello back from claude #{System.unique_integer()}"

      reply_conn =
        post(conn, "/api/cc-bridge/reply", %{
          "bridge_id" => bridge_id,
          "text" => reply_text
        })

      assert %{"ok" => true} = json_response(reply_conn, 200)

      # admin receives via user:events broadcast
      assert_receive {:message_received, %Message{sender: ^agent_uri} = msg}, 2_000
      assert msg.body.text == reply_text

      # And the Message landed in MessageStore (Chat.invoke(:send) wrote it)
      assert {:ok, _} = MessageStore.by_uri(msg.uri)

      # Cleanup
      delete(conn, "/api/cc-bridge/announce/#{bridge_id}")
    end
  end

  describe "reply without bound agent" do
    test "returns 422 with no-agent error", %{conn: conn} do
      bridge_id = "p2-noagent-#{System.unique_integer([:positive])}"

      # Announce WITHOUT agent_uri (legacy bridge)
      post(conn, "/api/cc-bridge/announce", %{"bridge_id" => bridge_id})

      reply_conn =
        post(conn, "/api/cc-bridge/reply", %{
          "bridge_id" => bridge_id,
          "text" => "no agent should bounce"
        })

      assert json_response(reply_conn, 422) == %{
               "ok" => false,
               "error" => "bridge has no agent bound; announce with agent_uri"
             }

      delete(conn, "/api/cc-bridge/announce/#{bridge_id}")
    end
  end

  describe "disconnect with bound agent" do
    test "terminates Agent Kind + unbinds", %{conn: conn} do
      bridge_id = "p2-disc-#{System.unique_integer([:positive])}"
      agent_uri_str = "agent://cc-disc-#{System.unique_integer([:positive])}"

      post(conn, "/api/cc-bridge/announce", %{
        "bridge_id" => bridge_id,
        "agent_uri" => agent_uri_str
      })

      agent_uri = URI.new!(agent_uri_str)
      assert {:ok, _} = KindRegistry.lookup(agent_uri)

      conn = delete(conn, "/api/cc-bridge/announce/#{bridge_id}")
      assert %{"ok" => true} = json_response(conn, 200)

      # KindRegistry cleared (terminate_child propagates to put_new entry release)
      assert :error =
               wait_until(fn ->
                 case KindRegistry.lookup(agent_uri) do
                   :error -> :error
                   _ -> nil
                 end
               end)

      # Binding gone
      assert :error = BridgeServer.bridge_for_agent(agent_uri)
    end
  end

  defp wait_until(fun, retries \\ 100) do
    case fun.() do
      nil when retries > 0 ->
        Process.sleep(10)
        wait_until(fun, retries - 1)

      nil ->
        flunk("wait_until timed out")

      value ->
        value
    end
  end
end
