defmodule EzagentCore.Repo.Migrations.Phase4Users do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :uri, :string, null: false
      add :password_hash, :string
      add :caps_json, :text, null: false, default: "[]"
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:uri])

    # NOTE: original migration seeded an admin row at
    # `entity://user/default/admin`. That seed was removed in Phase 9
    # PR-8 (SPEC v3 §13) when admin moved to
    # `entity://user/system/admin` (Keycloak realm-admin model). The
    # boot-time `ensure_admin_user/0` in
    # `EzagentDomainIdentity.Application` now creates admin via
    # `Ezagent.Users.create/3`, which populates the Phase 9 PR-6
    # `workspace_uri` column and uses the canonical admin URI from
    # `Ezagent.Entity.User.admin_uri/0`.
    #
    # Fresh clones get the right URI from boot. Pre-Phase-9 DBs get
    # the legacy row deleted by
    # `phase9_remove_legacy_admin_seed` migration.
  end
end
