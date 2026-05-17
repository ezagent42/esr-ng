defmodule EsrCore.Repo.Migrations.Phase6RoutingRuleWorkspaceScope do
  use Ecto.Migration

  def change do
    # Phase 6 PR 8: per-rule workspace scope.
    #
    # `workspace_uri` is nullable: null means "applies globally"
    # (current behavior — backward-compat). Non-null means the rule
    # only fires when the resolve context names that workspace.
    #
    # This is the structural piece that lets multi-tenant deployments
    # keep per-workspace routing isolated without scheme-prefix hacks.
    alter table(:routing_rules) do
      add :workspace_uri, :string
    end

    create index(:routing_rules, [:workspace_uri], name: :routing_rules_workspace_uri_index)
  end
end
