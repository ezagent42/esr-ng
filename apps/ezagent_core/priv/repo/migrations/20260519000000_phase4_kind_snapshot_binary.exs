defmodule EzagentCore.Repo.Migrations.Phase4KindSnapshotBinary do
  use Ecto.Migration

  def change do
    # Phase 4-completion Spec 04 §2.A: add a lossless binary column
    # (`:erlang.term_to_binary/1` round-trip) alongside the existing
    # JSON `:map` column. New writes use `state_binary`; reads prefer
    # binary then fall back to `:map`. Phase 5+ drops `state` once all
    # rows are migrated.
    alter table(:kind_snapshots) do
      add :state_binary, :binary
      add :inserted_at, :utc_datetime_usec
    end
  end
end
