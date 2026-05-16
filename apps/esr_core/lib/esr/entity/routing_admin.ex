defmodule Esr.Entity.RoutingAdmin do
  @moduledoc """
  RoutingAdmin Kind — Phase 5 PR 4 synthetic singleton for per-rule
  cap check (Spec 05 Part B Q-RT-3 落地).

  All routing rule mutations(add/delete/disable/enable)now go through
  `Esr.Invocation.dispatch` to `routing-admin://default/behavior/routing_admin/<action>`,
  which fires the Phase 3d real CapBAC check at dispatch step 5.5.

  - Admin (`user://admin` with triple-`:any` cap) — passes
  - Non-admin without `routing_admin.routing_admin` cap — gets
    `{:error, :unauthorized}` and an audit row at `[:esr, :authz, :denied]`

  Single instance: `routing-admin://default`. Spawned at boot by
  `EsrCore.Application.start`.
  """

  @behaviour Esr.Kind

  @impl Esr.Kind
  def type_name, do: :routing_admin

  @impl Esr.Kind
  def behaviors, do: [Esr.Behavior.RoutingAdmin]

  @impl Esr.Kind
  def persistence, do: :ephemeral

  @impl Esr.Kind
  def uri_from_args(args), do: Map.fetch!(args, :uri)

  @doc "The singleton URI for routing admin operations."
  def default_uri, do: URI.parse("routing-admin://default")
end
