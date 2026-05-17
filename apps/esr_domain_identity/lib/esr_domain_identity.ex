defmodule EsrDomainIdentity do
  @moduledoc """
  Identity domain — User Kind + caps + provisioning.

  Public surface:
  - `Esr.Entity.User` — User Kind
  - `Esr.Behavior.Identity` — list_caps / has_cap? actions
  - `Esr.Identity` — facade for CapBAC checks
  - `Esr.Users` — SQLite provisioning (login lookup, bcrypt)

  Phase 6 PR 2: extracted from esr_core. See SPEC.
  """
end
