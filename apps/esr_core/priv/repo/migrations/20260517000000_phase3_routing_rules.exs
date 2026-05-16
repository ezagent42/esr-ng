defmodule EsrCore.Repo.Migrations.Phase3RoutingRules do
  use Ecto.Migration

  def change do
    create table(:routing_rules) do
      add :table_name, :string, null: false
      add :matcher_data, :map, null: false
      add :receivers, {:array, :string}, null: false, default: []
      add :created_by, :string
      add :created_at, :utc_datetime_usec, null: false
    end

    create index(:routing_rules, [:table_name])
  end
end
