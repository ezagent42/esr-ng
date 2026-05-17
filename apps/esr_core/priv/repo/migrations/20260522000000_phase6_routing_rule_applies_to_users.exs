defmodule EsrCore.Repo.Migrations.Phase6RoutingRuleAppliesToUsers do
  use Ecto.Migration

  def change do
    # Phase 6 PR 5: per-rule sender filter.
    #
    # `applies_to_users` is a JSON-encoded list of sender URIs the rule
    # is restricted to. Empty list (the default) means "applies to every
    # sender" — same behavior as today. A non-empty list means the rule
    # only fires when `msg.sender` is in the set, which makes per-user
    # routing trivial: same matcher with different per-user receivers
    # become separate rows, no scheme bloat.
    alter table(:routing_rules) do
      add :applies_to_users, :text, null: false, default: "[]"
    end
  end
end
