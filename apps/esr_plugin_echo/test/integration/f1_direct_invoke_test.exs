defmodule EsrPluginEcho.Integration.F1DirectInvokeTest do
  @moduledoc """
  PLAN-internal checkpoint per phase-specs/phase1/PLAN.md §1a-step 4.

  Verifies F1 (text round-trip via Echo) works through the full
  dispatch path WITHOUT LiveView:

  - URI parsed
  - KindRegistry → Echo instance pid
  - GenServer.call routes to Kind.Runtime.handle_dispatch
  - BehaviorRegistry lookup finds Esr.Behavior.Echo
  - authz stub grants (emits :stub_grant)
  - args validated against @interface
  - Behavior.invoke runs, slice updated
  - telemetry [:esr, :invoke, :stop] emitted
  - Audit handler broadcasts to PubSub
  - Audit.Writer flushes batch to SQLite
  - SELECT FROM invocations finds the row

  This integration test must pass before moving on to step 5
  (LiveView). If it's red, the LiveView path will also be red because
  the dispatch backbone isn't working.
  """

  use ExUnit.Case

  alias Esr.Invocation
  alias EsrPluginEcho.Application, as: EchoApp

  setup do
    # Subscribe to the audit stream before invocation so we see the
    # event the dispatch will emit.
    :ok = Phoenix.PubSub.subscribe(EsrCore.PubSub, Esr.Audit.stream_topic())

    # Sandbox checkout — Audit.Writer is a long-lived GenServer that
    # needs to be allowed on this connection for SQLite writes to
    # succeed during the test. Wait for ready before we proceed.
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(EsrCore.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(EsrCore.Repo, {:shared, self()})

    :ok
  end

  test "F1: dispatch :say to agent://echo, get reply, see audit event + SQLite row" do
    target = URI.parse("#{URI.to_string(EchoApp.default_uri())}/behavior/echo/say")

    inv = %Invocation{
      target: target,
      mode: :call,
      args: %{msg: "hello"},
      ctx: %{
        caller: Esr.Entity.User.admin_uri(),
        caps: Esr.Entity.User.admin_caps(),
        reply: {:caller_inbox, self()}
      }
    }

    # Step 1: dispatch returns the echoed result synchronously.
    assert {:ok, %{echo: "hello"}} = Invocation.dispatch(inv)

    # Step 2: audit handler broadcasts to esr:audit:stream.
    assert_receive {:audit_event, audit_event}, 500
    assert audit_event.event == [:esr, :invoke, :stop]
    assert audit_event.metadata.target == "agent://echo/behavior/echo/say"
    assert audit_event.metadata.action == :say

    # Step 3: wait for Audit.Writer batch flush (100ms) + 50ms slack,
    # then query invocations table.
    Process.sleep(200)

    rows =
      EsrCore.Repo.query!(
        "SELECT target, action, authz, duration_us FROM invocations " <>
          "WHERE target LIKE 'agent://echo%' ORDER BY id DESC LIMIT 1"
      ).rows

    assert [[target_col, action_col, authz_col, duration_col]] = rows
    assert target_col == "agent://echo/behavior/echo/say"
    assert action_col == "say"
    assert authz_col == "stub_grant"
    assert is_integer(duration_col) and duration_col > 0
  end

  test "F1 via :cast — reply lands in caller_inbox" do
    target = URI.parse("#{URI.to_string(EchoApp.default_uri())}/behavior/echo/say")

    inv = %Invocation{
      target: target,
      mode: :cast,
      args: %{msg: "via-cast"},
      ctx: %{
        caller: Esr.Entity.User.admin_uri(),
        caps: Esr.Entity.User.admin_caps(),
        reply: {:caller_inbox, self()}
      }
    }

    assert :ok = Invocation.dispatch(inv)
    assert_receive {:esr_reply, {:ok, %{echo: "via-cast"}}}, 500
    assert_receive {:audit_event, %{event: [:esr, :invoke, :stop]}}, 500
  end

  test "F1 invalid args fail-stop at validator (does not reach Echo slice)" do
    target = URI.parse("#{URI.to_string(EchoApp.default_uri())}/behavior/echo/say")

    inv = %Invocation{
      target: target,
      mode: :call,
      # `:msg` should be a string per @interface; pass int to fail.
      args: %{msg: 42},
      ctx: %{
        caller: Esr.Entity.User.admin_uri(),
        caps: Esr.Entity.User.admin_caps(),
        reply: {:caller_inbox, self()}
      }
    }

    assert {:error, {:invalid_args, violations}} = Invocation.dispatch(inv)
    assert [{[:msg], {:type_mismatch, _}}] = violations
  end
end
