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

    # Seed admin row. caps_json is empty; admin uses User.admin_caps/0
    # at runtime (structural, not data-driven). password_hash is NULL
    # initially — must be set via `mix ezagent.user.set_password entity://user/default/admin --password X`
    # before /login accepts the admin (per Spec 05 Q-MU-1).
    execute """
            INSERT INTO users (uri, password_hash, caps_json, inserted_at, updated_at)
            VALUES ('entity://user/default/admin', NULL, '[]',
                    strftime('%Y-%m-%d %H:%M:%f', 'now'),
                    strftime('%Y-%m-%d %H:%M:%f', 'now'))
            """,
            "DELETE FROM users WHERE uri = 'entity://user/default/admin'"
  end
end
