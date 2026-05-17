defmodule EsrDomainChat.Integration.RoutingBootTest do
  @moduledoc """
  Phase 3a-step 4: boot integration — chat plugin must declare two
  RoutingRegistry tables (MentionRouting + SessionRouting) at app
  start so plugin authors / admin tooling can write to them.
  """

  use ExUnit.Case
  alias Esr.RoutingRegistry

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(EsrCore.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(EsrCore.Repo, {:shared, self()})
    :ok
  end

  test "MentionRouting table is declared at chat plugin boot" do
    # list_all raises ArgumentError if not declared; reaching here
    # without raise = table exists
    assert is_list(RoutingRegistry.list_all(EsrDomainChat.Routing.MentionRouting))
  end

  test "SessionRouting table is declared at chat plugin boot" do
    assert is_list(RoutingRegistry.list_all(EsrDomainChat.Routing.SessionRouting))
  end

  test "DefaultRules.bootstrap is idempotent" do
    assert :ok = EsrDomainChat.DefaultRules.bootstrap()
    assert :ok = EsrDomainChat.DefaultRules.bootstrap()
  end
end
