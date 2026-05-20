defmodule EzagentCore.Repo.Migrations.Pr141SchemeMigrationCleanRebuild do
  @moduledoc """
  PR #141 SPEC v2 §5.11 — "no backward compatibility, clean rebuild".

  This migration is a **marker** for the URI scheme migration cutover
  (user:// + agent:// merged into entity://). Per SPEC §5.11 the
  authoritative path is `mix ezagent.db.reset` (drops + recreates DB
  from scratch); this migration intentionally does NOT rewrite
  legacy URIs in existing rows because there should not be any.

  ## Why a marker migration at all

  Ecto's schema_migrations table is the durable record of which
  migrations have been applied. Having PR #141 in that list documents
  the cutover for future devs reading the migration log. The
  alternative — no migration — is indistinguishable from "PR #141
  forgot to migrate" in a year.

  ## What `mix ezagent.db.reset` does instead

  Drops the SQLite file, recreates it, replays every migration
  (this marker included) starting from a clean slate. The admin
  User seed in `phase4_users` now writes `entity://user/default/admin`
  directly (PR #141 in-place rewrite of the seed string).
  """

  use Ecto.Migration
  require Logger

  def up do
    Logger.info(
      "PR141 marker migration applied — URI scheme cutover. " <>
        "If this DB contains any legacy user://X or agent://Y rows, run " <>
        "`mix ezagent.db.reset` to wipe + rebuild."
    )

    :ok
  end

  def down do
    Logger.warning(
      "PR141 migration is not reversible — the entity:// scheme replaces " <>
        "user:// + agent:// across the codebase; rolling back would orphan " <>
        "every reference to those schemes."
    )

    :ok
  end
end
