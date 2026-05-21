defmodule EzagentCore.Repo.Migrations.Phase9Pr8WorkspaceVisible do
  @moduledoc """
  Phase 9 PR-8 (SPEC v3 §13) — add `visible` field to workspaces.

  Hidden workspaces (currently only `workspace://system`) do not appear
  in the regular workspace selector dropdown for non-system members.
  Default `true` so existing rows (default + any operator-created
  workspaces) remain visible.
  """
  use Ecto.Migration

  def change do
    alter table(:workspaces) do
      # SQLite booleans are 0/1 integers. Default `true` keeps existing
      # rows visible without backfill; the system workspace is created
      # at boot with `visible: false`.
      add :visible, :boolean, null: false, default: true
    end
  end
end
