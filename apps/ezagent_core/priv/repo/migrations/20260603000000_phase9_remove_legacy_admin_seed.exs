defmodule EzagentCore.Repo.Migrations.Phase9RemoveLegacyAdminSeed do
  @moduledoc """
  Phase 9 PR-8 follow-up — remove the legacy `entity://user/default/admin`
  row that the original `phase4_users` migration seeded.

  Phase 9 PR-8 (SPEC v3 §13) moved the admin user to
  `entity://user/system/admin` (Keycloak realm-admin model). The chat
  Application's boot-time `ensure_admin_user/0` correctly creates the
  new admin row via `Ezagent.Users.create/3`.

  However the legacy `phase4_users` migration's hardcoded INSERT
  (frozen since the original Phase 4 schema) continued to seed the
  *old* URI. Result for a fresh `mix ecto.migrate`: TWO admin rows —
  the legacy `default/admin` (no password, 0 caps) and the correct
  `system/admin` (password + 2 caps). Visible as the duplicate in
  the `/identities/users` page.

  This migration:
  - Deletes any `entity://user/default/admin` row that exists
  - Idempotent (delete-where-exists)
  - Skips the matching `entity://user/system/admin` creation (the
    boot-time path handles it, with `workspace_uri: workspace://system`
    + bcrypt'd password)

  See also: `phase4_users.exs` got its hardcoded URI updated in the
  same commit as this migration was added — fresh clones start
  consistent.

  Wipe-rebuild precedent (per `feedback_let_it_crash_no_workarounds`):
  no backfill complexity. Either there's a legacy row → delete it; or
  there isn't → no-op. Forward-only.
  """
  use Ecto.Migration

  def up do
    execute("DELETE FROM users WHERE uri = 'entity://user/default/admin'")
  end

  def down do
    # Re-seed is intentionally NOT supported — Phase 9 doesn't keep
    # default/admin as a valid identity. Re-creating it would require
    # workspace_uri + caps + password handling that no longer applies.
    :ok
  end
end
