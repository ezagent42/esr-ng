defmodule EzagentDomainChat.Integration.RoutingBootTest do
  @moduledoc """
  Phase 3a-step 4: boot integration — chat plugin must declare two
  RoutingRegistry tables (MentionRouting + SessionRouting) at app
  start so plugin authors / admin tooling can write to them.
  """

  use ExUnit.Case
  alias Ezagent.RoutingRegistry

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(EzagentCore.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(EzagentCore.Repo, {:shared, self()})
    :ok
  end

  test "MentionRouting table is declared at chat plugin boot" do
    # list_all raises ArgumentError if not declared; reaching here
    # without raise = table exists
    assert is_list(RoutingRegistry.list_all(EzagentDomainChat.Routing.MentionRouting))
  end

  test "SessionRouting table is declared at chat plugin boot" do
    assert is_list(RoutingRegistry.list_all(EzagentDomainChat.Routing.SessionRouting))
  end

  test "DefaultRules.bootstrap is idempotent" do
    assert :ok = EzagentDomainChat.DefaultRules.bootstrap()
    assert :ok = EzagentDomainChat.DefaultRules.bootstrap()
  end
end
