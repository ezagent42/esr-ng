defmodule Esr.Entity.User do
  @moduledoc """
  User Kind — Phase 1 stub.

  Implements the `Esr.Kind` `@behaviour` contract with empty Behaviors
  list (Phase 3d will add `Esr.Behavior.Identity`). Holds the
  admin-bootstrap constants `admin_uri/0` and `admin_caps/0` per
  Decision P1-D5 (no separate `Esr.Bootstrap` module — admin-specific
  knowledge is User-Kind-shaped).

  Phase 1 does **not** spawn any User Kind instance — there is no
  Identity Behavior yet, and dispatch reply paths in Phase 1 use
  `ctx.reply = {:caller_inbox, self()}` so no `KindRegistry.lookup`
  on `user://admin` happens.

  Phase 2 forward note (DECISIONS P1-D5): if Chat Behavior arrives,
  decide spawn-admin-on-boot vs special-case-admin-URI-in-reply.

  ## Phase 1 callbacks left intentionally trivial

  `type_name :user`, `behaviors []`, `persistence {:snapshot, :on_change}`.
  Phase 3d will append `Esr.Behavior.Identity` to `behaviors/0` and add
  `bootstrap_admin_if_needed/0` — append-only evolution per P1-D5.
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

  # --- Esr.Kind callbacks (Phase 1 stub) -----------------------------
  @behaviour Esr.Kind

  @impl Esr.Kind
  def type_name, do: :user

  @impl Esr.Kind
  def behaviors, do: []

  @impl Esr.Kind
  def persistence, do: {:snapshot, :on_change}
end
