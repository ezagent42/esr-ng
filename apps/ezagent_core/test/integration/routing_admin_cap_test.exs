defmodule Ezagent.Integration.RoutingAdminCapTest do
  @moduledoc """
  Phase 5 PR 4 invariant test (Spec 5B Q-RT-3 落地 gate).

  Per memory `feedback_completion_requires_invariant_test`: route
  mutations now go through the synthetic `Ezagent.Entity.RoutingAdmin`
  Kind → CapBAC step 5.5 fires → non-admin without routing_admin cap
  gets `:unauthorized` and audit row written.

  If this test breaks, the per-rule cap-protect is broken regardless
  of green LV tests (admin's all-cap always passes; the gate is the
  non-admin path).
  """

  use EzagentCore.DataCase, async: false

  alias Ezagent.{Invocation, Routing.Matcher}
  alias EzagentDomainChat.Routing.MentionRouting

  defp admin_ctx do
    %{
      caller: Ezagent.Entity.User.admin_uri(),
      caps: Ezagent.Entity.User.admin_caps(),
      reply: {:caller_inbox, self()}
    }
  end

  defp non_admin_ctx do
    %{
      caller: URI.parse("entity://user/non-admin-test"),
      caps: MapSet.new(),
      reply: {:caller_inbox, self()}
    }
  end

  defp routing_admin_target(action) do
    URI.parse(
      "#{URI.to_string(Ezagent.Entity.RoutingAdmin.default_uri())}/behavior/routing_admin/#{action}"
    )
  end

  test "admin can add a rule via RoutingAdmin dispatch" do
    matcher =
      Matcher.text_contains("admin-test-#{System.unique_integer([:positive])}")

    assert {:ok, %{id: id}} =
             Invocation.dispatch(%Invocation{
               target: routing_admin_target("add_rule"),
               mode: :call,
               args: %{
                 table: MentionRouting,
                 matcher_json: Matcher.to_json(matcher),
                 receivers: ["session://cap-test"]
               },
               ctx: admin_ctx()
             })

    assert is_integer(id)
  end

  test "non-admin gets :unauthorized when adding rule" do
    assert {:error, :unauthorized} =
             Invocation.dispatch(%Invocation{
               target: routing_admin_target("add_rule"),
               mode: :call,
               args: %{
                 table: MentionRouting,
                 matcher_json: Matcher.to_json(Matcher.always()),
                 receivers: ["session://x"]
               },
               ctx: non_admin_ctx()
             })
  end

  test "non-admin gets :unauthorized for delete_rule" do
    assert {:error, :unauthorized} =
             Invocation.dispatch(%Invocation{
               target: routing_admin_target("delete_rule"),
               mode: :call,
               args: %{table: MentionRouting, id: 999_999},
               ctx: non_admin_ctx()
             })
  end

  test "RoutingAdmin singleton is alive at boot at routing-admin://default" do
    uri = Ezagent.Entity.RoutingAdmin.default_uri()
    assert {:ok, _pid} = Ezagent.KindRegistry.lookup(uri)
  end

  test "RoutingAdmin Kind type_name is :routing_admin" do
    assert Ezagent.Entity.RoutingAdmin.type_name() == :routing_admin
  end

  test "required_cap_shape helper returns matchable shape" do
    shape = Ezagent.Behavior.RoutingAdmin.required_cap_shape()
    assert shape.kind == :routing_admin
    assert shape.behavior == Ezagent.Behavior.RoutingAdmin
    assert %URI{scheme: "routing-admin"} = shape.instance
  end
end
