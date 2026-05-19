defmodule EzagentPluginEcho.Integration.F1DirectInvokeTest do
  @moduledoc """
  PLAN-internal checkpoint per phase-specs/phase1/PLAN.md §1a-step 4.

  Verifies F1 (text round-trip via Echo) works through the full
  dispatch path WITHOUT LiveView:

  - URI parsed
  - KindRegistry → Echo instance pid
  - GenServer.call routes to Kind.Runtime.handle_dispatch
  - BehaviorRegistry lookup finds Ezagent.Behavior.Echo
  - authz stub grants (emits :stub_grant)
  - args validated against @interface
  - Behavior.invoke runs, slice updated
  - telemetry [:ezagent, :invoke, :stop] emitted
  - Audit handler broadcasts to PubSub
  - Audit.Writer flushes batch to SQLite
  - SELECT FROM invocations finds the row

  This integration test must pass before moving on to step 5
  (LiveView). If it's red, the LiveView path will also be red because
  the dispatch backbone isn't working.
  """

  use ExUnit.Case

  alias Ezagent.Invocation
  alias EzagentPluginEcho.Application, as: EchoApp

  setup do
    # Subscribe to the audit stream before invocation so we see the
    # event the dispatch will emit.
    :ok = Phoenix.PubSub.subscribe(EzagentCore.PubSub, Ezagent.Audit.stream_topic())

    # Sandbox checkout — Audit.Writer is a long-lived GenServer that
    # needs to be allowed on this connection for SQLite writes to
    # succeed during the test. Wait for ready before we proceed.
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(EzagentCore.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(EzagentCore.Repo, {:shared, self()})

    :ok
  end

  test "F1: dispatch :say to entity://agent/echo_default, get reply, see audit event + SQLite row" do
    target = URI.parse("#{URI.to_string(EchoApp.default_uri())}?action=echo.say")

    inv = %Invocation{
      target: target,
      mode: :call,
      args: %{msg: "hello"},
      ctx: %{
        caller: Ezagent.Entity.User.admin_uri(),
        caps: Ezagent.Entity.User.admin_caps(),
        reply: {:caller_inbox, self()}
      }
    }

    # Step 1: dispatch returns the echoed result synchronously.
    assert {:ok, %{echo: "hello"}} = Invocation.dispatch(inv)

    # Step 2: audit handler broadcasts to esr:audit:stream.
    # Phase 3d: dispatch emits two audit events — :authz :granted first
    # (when cap check passes) then :invoke :stop (when invoke succeeds).
    # Both arrive; we care about the :stop event's metadata.
    assert_receive {:audit_event, %{event: [:ezagent, :authz, :granted]}}, 500
    assert_receive {:audit_event, %{event: [:ezagent, :invoke, :stop]} = stop_event}, 500
    assert stop_event.metadata.target == "entity://agent/echo_default?action=echo.say"
    assert stop_event.metadata.action == :say

    # Step 3: wait for Audit.Writer batch flush (100ms) + 50ms slack,
    # then query invocations table.
    Process.sleep(200)

    rows =
      EzagentCore.Repo.query!(
        "SELECT target, action, authz, duration_us FROM invocations " <>
          "WHERE target LIKE 'entity://agent/echo_default%' ORDER BY id DESC LIMIT 1"
      ).rows

    assert [[target_col, action_col, authz_col, duration_col]] = rows
    assert target_col == "entity://agent/echo_default?action=echo.say"
    assert action_col == "say"
    # Phase 3d: hard flip removed :stub_grant in favor of real "granted"
    # from cap check. invocations.authz column is "granted" for the
    # success path (caller had matching cap).
    assert authz_col == "granted"
    assert is_integer(duration_col) and duration_col > 0
  end

  test "F1 via :cast — reply lands in caller_inbox" do
    target = URI.parse("#{URI.to_string(EchoApp.default_uri())}?action=echo.say")

    inv = %Invocation{
      target: target,
      mode: :cast,
      args: %{msg: "via-cast"},
      ctx: %{
        caller: Ezagent.Entity.User.admin_uri(),
        caps: Ezagent.Entity.User.admin_caps(),
        reply: {:caller_inbox, self()}
      }
    }

    assert :ok = Invocation.dispatch(inv)
    assert_receive {:ezagent_reply, {:ok, %{echo: "via-cast"}}}, 500
    assert_receive {:audit_event, %{event: [:ezagent, :invoke, :stop]}}, 500
  end

  test "F1 invalid args fail-stop at validator (does not reach Echo slice)" do
    target = URI.parse("#{URI.to_string(EchoApp.default_uri())}?action=echo.say")

    inv = %Invocation{
      target: target,
      mode: :call,
      # `:msg` should be a string per @interface; pass int to fail.
      args: %{msg: 42},
      ctx: %{
        caller: Ezagent.Entity.User.admin_uri(),
        caps: Ezagent.Entity.User.admin_caps(),
        reply: {:caller_inbox, self()}
      }
    }

    assert {:error, {:invalid_args, violations}} = Invocation.dispatch(inv)
    assert [{[:msg], {:type_mismatch, _}}] = violations
  end
end
