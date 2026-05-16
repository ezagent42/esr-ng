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
