defmodule Esr.InvocationTest do
  use ExUnit.Case
  alias Esr.{Invocation, Test.TestKind, Test.TestBehavior}

  setup do
    uri = URI.parse("agent://invocation-test-#{System.unique_integer([:positive])}")
    :ok = Esr.BehaviorRegistry.register(TestKind, :noop, TestBehavior)
    :ok = Esr.BehaviorRegistry.register(TestKind, :fail, TestBehavior)

    {:ok, _pid} = Esr.Kind.Server.start_link({TestKind, %{uri: uri}})
    :ok = wait_until_ready(uri)

    {:ok, instance_uri: uri, target: URI.parse("#{URI.to_string(uri)}/behavior/test/noop")}
  end

  describe "dispatch/1 — happy path" do
    test ":call returns the invoke result", %{target: target} do
      inv = %Invocation{
        target: target,
        mode: :call,
        args: %{msg: "hi"},
        ctx: ctx_for(self())
      }

      assert {:ok, %{echoed: "hi"}} = Invocation.dispatch(inv)
    end

    test ":cast returns :ok and delivers via caller_inbox reply", %{target: target} do
      inv = %Invocation{
        target: target,
        mode: :cast,
        args: %{msg: "cast-msg"},
        ctx: ctx_for(self())
      }

      assert :ok = Invocation.dispatch(inv)
      assert_receive {:esr_reply, {:ok, %{echoed: "cast-msg"}}}, 500
    end
  end

  describe "dispatch/1 — error paths" do
    test ":no_such_actor for unknown URI" do
      inv = %Invocation{
        target: URI.parse("agent://does-not-exist/behavior/test/noop"),
        mode: :call,
        args: %{msg: "x"},
        ctx: ctx_for(self())
      }

      assert {:error, :no_such_actor} = Invocation.dispatch(inv)
    end

    test ":not_ready + :call → fail-fast (invariant #3)", %{instance_uri: uri} do
      # Force the instance back into not_ready to exercise the
      # invariant — caller doesn't actually need it ready for the test.
      :ok = Esr.ReadyGate.put(uri, :not_ready)

      inv = %Invocation{
        target: URI.parse("#{URI.to_string(uri)}/behavior/test/noop"),
        mode: :call,
        args: %{msg: "x"},
        ctx: ctx_for(self())
      }

      assert {:error, :not_ready} = Invocation.dispatch(inv)

      # Restore for cleanup.
      :ok = Esr.ReadyGate.mark_ready(uri)
    end

    test ":not_ready + :cast → buffered (no error)", %{instance_uri: uri} do
      :ok = Esr.ReadyGate.put(uri, :not_ready)

      target = URI.parse("#{URI.to_string(uri)}/behavior/test/noop")

      inv = %Invocation{
        target: target,
        mode: :cast,
        args: %{msg: "buffered"},
        ctx: ctx_for(self())
      }

      assert :ok = Invocation.dispatch(inv)
      assert Esr.PendingDelivery.buffer_size(uri) >= 1

      # Restore.
      _ = Esr.PendingDelivery.flush(uri)
      :ok = Esr.ReadyGate.mark_ready(uri)
    end

    test ":subscribe / :introspect return :unsupported_mode in Phase 1", %{target: target} do
      inv = %Invocation{
        target: target,
        mode: :subscribe,
        args: %{},
        ctx: ctx_for(self())
      }

      assert {:error, :unsupported_mode} = Invocation.dispatch(inv)
    end
  end

  describe "dispatch/1 — idempotency" do
    test "duplicate idempotency_key returns :duplicate_ignored, doesn't re-invoke", %{
      target: target
    } do
      key = "test-idem-#{System.unique_integer([:positive])}"

      ctx = ctx_for(self()) |> Map.put(:idempotency_key, key)

      inv = %Invocation{target: target, mode: :call, args: %{msg: "once"}, ctx: ctx}

      # First call records and dispatches.
      assert {:ok, %{echoed: "once"}} = Invocation.dispatch(inv)

      # Second call detects duplicate and short-circuits.
      assert {:ok, :duplicate_ignored} = Invocation.dispatch(inv)
    end
  end

  describe "reply/2 — 7-case table" do
    test ":caller_inbox sends {:esr_reply, result}" do
      :ok = Invocation.reply(%{reply: {:caller_inbox, self()}}, :hello)
      assert_receive {:esr_reply, :hello}
    end

    test ":phoenix_pubsub broadcasts to topic" do
      topic = "esr:test:#{System.unique_integer([:positive])}"
      :ok = Phoenix.PubSub.subscribe(EsrCore.PubSub, topic)

      :ok = Invocation.reply(%{reply: {:phoenix_pubsub, topic}}, :hi)

      assert_receive {:esr_reply, :hi}
    end

    test ":ignore is a no-op" do
      assert :ok = Invocation.reply(%{reply: :ignore}, :anything)
    end

    test "phase-deferred targets raise" do
      assert_raise ArgumentError, ~r/not yet implemented/, fn ->
        Invocation.reply(%{reply: {:plug_conn, :fake}}, :x)
      end
    end
  end

  defp ctx_for(pid) do
    %{
      caller: URI.parse("user://admin"),
      caps: Esr.Entity.User.admin_caps(),
      reply: {:caller_inbox, pid}
    }
  end

  defp wait_until_ready(uri) do
    case Esr.ReadyGate.status(uri) do
      :ready ->
        :ok

      _ ->
        Process.sleep(5)
        wait_until_ready(uri)
    end
  end
end
