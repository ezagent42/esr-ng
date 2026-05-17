defmodule EsrDomainChat.Integration.RealClaudeHotfixesTest do
  @moduledoc """
  Regression tests for Phase 3d hotfixes exposed by real-claude e2e
  on 2026-05-16:

  1. **Source session in push_to_claude meta** — Chat.invoke(:receive)
     on Agent Kind must include `"session"` in the meta map so claude
     can fill `session_uris` correctly on reply. Previously claude
     guessed (badly) from sender URI.

  2. **Reply dispatch failure visibility** — when a claude reply
     targets a non-existent session (claude guessed wrong), the
     subsequent Chat handle_kind_message dispatch returned
     `{:error, :no_such_actor}` and was silently dropped. Now emits
     `[:esr, :chat, :reply_dispatch_failed]` telemetry.
  """

  use ExUnit.Case
  alias Esr.{Invocation, KindRegistry, Message}
  alias Esr.Behavior.Chat
  alias Esr.Entity.{Session, User}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(EsrCore.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(EsrCore.Repo, {:shared, self()})
    :ok
  end

  describe "fix #1: push_to_claude meta includes source session" do
    test "Chat.invoke(:receive) on Agent passes session in meta to bridge" do
      # Subscribe to a per-bridge to_claude topic before triggering;
      # the bridge plugin broadcasts the meta on this topic via
      # Esr.Bridge.V1Prototype.Server.push_to_claude/3.
      bridge_id = "hotfix-meta-#{System.unique_integer([:positive])}"
      agent_uri = URI.new!("agent://meta-test-#{System.unique_integer([:positive])}")
      session_uri = URI.new!("session://meta-source-#{System.unique_integer([:positive])}")

      # Spawn Agent + bind to bridge_id
      {:ok, agent_pid} =
        DynamicSupervisor.start_child(
          EsrDomainChat.AgentSupervisor,
          {Esr.Kind.Server, {Esr.Entity.Agent, %{uri: agent_uri}}}
        )

      :ok = Esr.Bridge.V1Prototype.Server.bind_agent(bridge_id, agent_uri, agent_pid)

      # Subscribe to the topic the bridge fires on push
      topic = Esr.Bridge.V1Prototype.Server.to_claude_topic(bridge_id)
      :ok = Phoenix.PubSub.subscribe(EsrCore.PubSub, topic)

      # Now call Chat.invoke(:receive) directly. ctx must mimic what
      # Kind.Runtime injects + what Session.dispatch_receive sets for
      # ctx.caller (the source session).
      msg =
        Message.new(URI.new!("user://admin"), %{text: "hi cc-builder", attachments: []})

      ctx = %{
        caller: session_uri,
        caps: User.admin_caps(),
        reply: :ignore,
        kind_module: Esr.Entity.Agent,
        self_uri: agent_uri
      }

      assert {:ok, _} = Chat.invoke(:receive, %{}, %{message: msg}, ctx)

      # The bridge should have received the push event with our session
      assert_receive {:to_claude, %{meta: meta}}, 500
      assert meta["session"] == URI.to_string(session_uri)
      assert meta["sender"] == "user://admin"
      assert meta["message_uri"] == msg.uri

      # Cleanup
      _ = Esr.Bridge.V1Prototype.Server.unbind_agent(bridge_id)

      DynamicSupervisor.terminate_child(EsrDomainChat.AgentSupervisor, agent_pid)
    end
  end

  describe "fix #2: reply dispatch to non-existent session emits telemetry" do
    test "Chat.handle_kind_message catches :no_such_actor and emits :reply_dispatch_failed" do
      # Spawn an Agent
      agent_uri = URI.new!("agent://reply-fail-#{System.unique_integer([:positive])}")

      {:ok, agent_pid} =
        DynamicSupervisor.start_child(
          EsrDomainChat.AgentSupervisor,
          {Esr.Kind.Server, {Esr.Entity.Agent, %{uri: agent_uri}}}
        )

      # Attach telemetry handler before triggering
      test_pid = self()
      handler_id = "hotfix2-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        handler_id,
        [:esr, :chat, :reply_dispatch_failed],
        fn _event, _measurements, meta, _config ->
          send(test_pid, {:telemetry, meta})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      # Send a reply targeting a session that doesn't exist
      nonexistent = "session://does-not-exist-#{System.unique_integer([:positive])}"

      send(agent_pid, {:reply_received, [nonexistent], "ack to nowhere", nil})

      # telemetry should fire within a moment
      assert_receive {:telemetry, meta}, 500
      assert meta.target_session == nonexistent
      assert meta.agent == URI.to_string(agent_uri)
      assert meta.reason in [:no_such_actor, {:error, :no_such_actor}]

      DynamicSupervisor.terminate_child(EsrDomainChat.AgentSupervisor, agent_pid)
    end
  end
end
