defmodule Esr.Entity.User do
  @moduledoc """
  User Kind — Phase 4-completion stable form.

  Implements `Esr.Kind` with Identity Behavior (Phase 3d added,
  Decision #24). Holds the admin-bootstrap constants `admin_uri/0` and
  `admin_caps/0` per Decision P1-D5 (no separate `Esr.Bootstrap` module
  — admin-specific knowledge is User-Kind-shaped).

  - `type_name :user`
  - `behaviors [Esr.Behavior.Identity]` — caps live in slice state
  - `persistence {:snapshot, :on_change}` — Phase 4-completion PR 2
    landed real snapshot impl; granted caps survive restart

  Non-admin Users (Phase 4-completion PR 4-5):
  - Provisioned via `mix esr.user.create user://X --password Y --caps ...`
  - Authenticated via `/login` (`EsrWeb.SessionController` +
    `Esr.Users.verify_password/2`)
  - Their caps live in `Esr.Users.caps_json` SQLite column AND mirror
    into Identity slice via `init_slice/1`
  """

  @admin_uri URI.parse("user://admin")
  @system_bootstrap_uri URI.parse("system://bootstrap")

  # Static granted_at — admin capability is a structural bootstrap, not
  # a time-varying grant. Same value across boots so tests/fixtures stay
  # deterministic.
  @admin_granted_at ~U[2026-01-01 00:00:00Z]

  @doc "Bootstrap admin principal URI: `user://admin`."
  @spec admin_uri() :: URI.t()
  def admin_uri, do: @admin_uri

  @doc """
  Admin's structural all-caps capability set.

  One capability with triple-`:any` granted by `system://bootstrap` —
  this is the invariant `Esr.Capability.revoke/2` refuses to remove.
  Returned as a `MapSet` so `Esr.Capability.matches?/2` lookups via
  `Enum.any?(caps, ...)` are O(n) of constant n=1 in Phase 1.
  """
  @spec admin_caps() :: MapSet.t(Esr.Capability.t())
  def admin_caps do
    MapSet.new([
      %Esr.Capability{
        kind: :any,
        behavior: :any,
        instance: :any,
        granted_by: @system_bootstrap_uri,
        granted_at: @admin_granted_at
      }
    ])
  end

  @doc """
  Default caps every non-admin User starts life with.

  PR 27 (Allen 2026-05-18): every ESR User is, by construction, a
  principal that can attempt to participate in a session — without
  this baseline cap, even the most basic Feishu-delegate / CLI-test
  path is unauthorized and silently drops. Making this a User Kind
  structural default keeps every creation site (LV, mix task, Feishu
  bind) consistent without forcing each caller to remember the
  boilerplate.

  This is NOT an authorization escape hatch. The cap says "this
  principal may attempt to invoke session behaviors on some session
  instance"; whether the message actually lands depends on session
  membership and routing rules, not on this cap. Admin's wildcard
  `admin_caps/0` is the only true escape hatch, and is granted only
  to `user://admin`.

  **Behavior wildcard**: `:any` follows the existing project
  convention (cf. `feishu_chat:any` granted by `BindingPolicy`).
  Modeling specific behaviors here would require esr_domain_identity
  to depend on esr_domain_chat (circular), or runtime
  BehaviorRegistry lookups at user-creation time (boot-order
  fragile). `:any` plus a narrow `:kind` scope is the consistent
  trade-off the codebase already uses.

  Prepended to user-supplied caps in `Esr.Domain.Identity.Users.create/3`.
  Idempotently re-granted by Feishu `BindingPolicy.apply/2` to handle
  pre-PR-27 users that were created without it.
  """
  @spec default_caps() :: [Esr.Capability.t()]
  def default_caps do
    [
      %Esr.Capability{
        kind: :session,
        behavior: :any,
        instance: :any,
        granted_by: @system_bootstrap_uri,
        granted_at: @admin_granted_at
      }
    ]
  end

  # --- Esr.Kind callbacks -----------------------------------------------
  @behaviour Esr.Kind

  @impl Esr.Kind
  def type_name, do: :user

  # Phase 3d: User Kinds carry Identity Behavior so caps live in slice
  # state (Decision #24). admin_caps/0 above still provides the
  # bootstrap value — chat plugin passes it as initial_caps when
  # spawning admin User.
  @impl Esr.Kind
  def behaviors, do: [Esr.Behavior.Identity]

  @impl Esr.Kind
  def persistence, do: {:snapshot, :on_change}
end
