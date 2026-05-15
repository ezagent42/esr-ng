defmodule EsrCore.Repo.Migrations.Phase1AuditDlqSnapshots do
  use Ecto.Migration

  def change do
    # --- invocations: append-only audit log per ARCHITECTURE.md §10.2 ---
    create table(:invocations, primary_key: false) do
      add :id, :integer, primary_key: true
      add :trace_id, :string
      add :caller, :string
      add :target, :string, null: false
      add :action, :string
      add :args, :map
      add :result, :map
      add :duration_us, :integer
      add :authz, :string
      add :exception, :map
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:invocations, [:inserted_at])
    create index(:invocations, [:target, :inserted_at])

    # --- dlq: failed / unroutable invocations, bounded FIFO ---
    create table(:dlq, primary_key: false) do
      add :id, :integer, primary_key: true
      add :reason, :string, null: false
      add :payload, :map, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:dlq, [:inserted_at])

    # --- kind_snapshots: persistent state per Kind instance ---
    # uri is PK (one current snapshot per instance); kind_type is the
    # stable type atom per Decision #62 (module name moves freely).
    create table(:kind_snapshots, primary_key: false) do
      add :uri, :string, primary_key: true
      add :kind_type, :string, null: false
      add :state, :map, null: false
      add :version, :integer, null: false, default: 0
      add :updated_at, :utc_datetime_usec, null: false
    end
  end
end
