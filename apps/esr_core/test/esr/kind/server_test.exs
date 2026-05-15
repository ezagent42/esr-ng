defmodule Esr.Kind.ServerTest do
  use ExUnit.Case
  alias Esr.Test.{TestKind, TestBehavior}

  setup do
    # Each test gets a unique URI so registry state doesn't leak.
    uri = URI.parse("agent://kind-server-test-#{System.unique_integer([:positive])}")

    # Wire TestKind/TestBehavior into the BehaviorRegistry for this test —
    # idempotent register so reruns are fine.
    :ok = Esr.BehaviorRegistry.register(TestKind, :noop, TestBehavior)
    :ok = Esr.BehaviorRegistry.register(TestKind, :fail, TestBehavior)
    :ok = Esr.BehaviorRegistry.register(TestKind, :raise, TestBehavior)

    {:ok, uri: uri}
  end

  test "init registers URI, marks not_ready, then announce_ready transitions", %{uri: uri} do
    {:ok, pid} = Esr.Kind.Server.start_link({TestKind, %{uri: uri}})

    # Wait for handle_continue to run.
    :ok = wait_until_ready(uri, 500)

    # Registered.
    assert {:ok, ^pid} = Esr.KindRegistry.lookup(uri)
    # Ready.
    assert :ready = Esr.ReadyGate.status(uri)
  end

  test "handle_call :esr_dispatch invokes behavior, updates slice, returns result", %{uri: uri} do
    {:ok, pid} = Esr.Kind.Server.start_link({TestKind, %{uri: uri}})
    :ok = wait_until_ready(uri, 500)

    inv = %Esr.Invocation{
      target: URI.parse("#{URI.to_string(uri)}/behavior/test/noop"),
      mode: :call,
      args: %{msg: "hello"},
      ctx: %{caller: URI.parse("user://admin"), caps: MapSet.new(), reply: :ignore}
    }

    assert {:ok, %{echoed: "hello"}} = GenServer.call(pid, {:esr_dispatch, inv})
  end

  test "handle_cast :esr_dispatch invokes behavior + replies to caller_inbox", %{uri: uri} do
    {:ok, pid} = Esr.Kind.Server.start_link({TestKind, %{uri: uri}})
    :ok = wait_until_ready(uri, 500)

    inv = %Esr.Invocation{
      target: URI.parse("#{URI.to_string(uri)}/behavior/test/noop"),
      mode: :cast,
      args: %{msg: "via-cast"},
      ctx: %{
        caller: URI.parse("user://admin"),
        caps: MapSet.new(),
        reply: {:caller_inbox, self()}
      }
    }

    GenServer.cast(pid, {:esr_dispatch, inv})

    assert_receive {:esr_reply, {:ok, %{echoed: "via-cast"}}}, 1000
  end

  test "PendingDelivery flush on announce_ready", %{uri: uri} do
    # Buffer a message *before* the server exists, then start the server —
    # the message should be drained during announce_ready.
    pre_inv = %Esr.Invocation{
      target: URI.parse("#{URI.to_string(uri)}/behavior/test/noop"),
      mode: :cast,
      args: %{msg: "pre-ready"},
      ctx: %{
        caller: URI.parse("user://admin"),
        caps: MapSet.new(),
        reply: {:caller_inbox, self()}
      }
    }

    :ok = Esr.PendingDelivery.buffer(uri, pre_inv)
    assert Esr.PendingDelivery.buffer_size(uri) == 1

    {:ok, _pid} = Esr.Kind.Server.start_link({TestKind, %{uri: uri}})

    # Buffered cast should be drained and flow through dispatch → reply.
    assert_receive {:esr_reply, {:ok, %{echoed: "pre-ready"}}}, 1000
    # Buffer should be empty after flush.
    assert Esr.PendingDelivery.buffer_size(uri) == 0
  end

  defp wait_until_ready(uri, timeout_ms) do
    poll(uri, System.monotonic_time(:millisecond) + timeout_ms)
  end

  defp poll(uri, deadline) do
    case Esr.ReadyGate.status(uri) do
      :ready ->
        :ok

      _ ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, :timeout}
        else
          Process.sleep(5)
          poll(uri, deadline)
        end
    end
  end
end
