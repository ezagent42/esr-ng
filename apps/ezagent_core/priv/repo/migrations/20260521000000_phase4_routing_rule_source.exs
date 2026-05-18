defmodule EzagentCore.Repo.Migrations.Phase4RoutingRuleSource do
  use Ecto.Migration

  def change do
    # Phase 4-completion PR 9 §C: distinguish system-default rules from
    # admin-edited rules. Without this, deleting a default rule via admin
    # gets re-seeded on next boot (DefaultRules.bootstrap checks "table
    # empty" which is broken for partial deletes).
    #
    # `source`:
    # - "system_default" — seeded by plugin's DefaultRules.bootstrap
    # - "admin" — written via CLI / LV
    #
    # `enabled`: lets admin disable a system_default rule without
    # deleting it (system_defaults are protected from delete; can be
    # disabled to opt out).
    alter table(:routing_rules) do
      add :source, :string, null: false, default: "admin"
      add :enabled, :boolean, null: false, default: true
    end
  end
end
