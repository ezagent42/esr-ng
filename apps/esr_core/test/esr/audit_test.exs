defmodule Esr.AuditTest do
  use ExUnit.Case

  setup do
    # Make sure the handler is attached (Application.start should have
    # done this; re-attach is idempotent).
    :ok = Esr.Audit.attach()
    Phoenix.PubSub.subscribe(EsrCore.PubSub, Esr.Audit.stream_topic())
    :ok
  end

  test "[:esr, :invoke, :stop] is broadcast to esr:audit:stream" do
    target = URI.parse("agent://audit-test")

    :telemetry.execute(
      [:esr, :invoke, :stop],
      %{duration_us: 123},
      %{
        target: target,
        caller: URI.parse("user://admin"),
        action: :test,
        kind_module: Foo,
        behavior_module: Bar,
        behavior_name: :foo
      }
    )

    assert_receive {:audit_event, event}, 500
    assert event.event == [:esr, :invoke, :stop]
    assert event.measurements == %{duration_us: 123}
    assert event.metadata.target == "agent://audit-test"
  end

  test "[:esr, :invoke, :error] is also broadcast" do
    target = URI.parse("agent://audit-test")

    :telemetry.execute(
      [:esr, :invoke, :error],
      %{duration_us: 7},
      %{target: target, caller: URI.parse("user://admin"), reason: :test_failure}
    )

    assert_receive {:audit_event, event}, 500
    assert event.event == [:esr, :invoke, :error]
  end

  test "stream_topic/0 is the canonical audit topic name" do
    assert Esr.Audit.stream_topic() == "esr:audit:stream"
  end
end
