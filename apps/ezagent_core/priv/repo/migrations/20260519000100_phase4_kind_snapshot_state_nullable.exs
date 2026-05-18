defmodule EzagentCore.Repo.Migrations.Phase4KindSnapshotStateNullable do
  use Ecto.Migration

  # SQLite has limited ALTER COLUMN support — rebuild via a temp
  # table + INSERT-SELECT (the standard SQLite pattern).
  #
  # All new writes target state_binary; the legacy :state column is
  # kept for backward-compat reading of any pre-existing rows.

  def up do
    execute """
    CREATE TABLE kind_snapshots_new (
      uri TEXT PRIMARY KEY,
      kind_type TEXT NOT NULL,
      state TEXT,
      state_binary BLOB,
      version INTEGER NOT NULL DEFAULT 0,
      inserted_at TEXT,
      updated_at TEXT NOT NULL
    )
    """

    execute """
    INSERT INTO kind_snapshots_new (uri, kind_type, state, state_binary, version, inserted_at, updated_at)
    SELECT uri, kind_type, state, state_binary, version, inserted_at, updated_at FROM kind_snapshots
    """

    execute "DROP TABLE kind_snapshots"
    execute "ALTER TABLE kind_snapshots_new RENAME TO kind_snapshots"
  end

  def down do
    :ok
  end
end
