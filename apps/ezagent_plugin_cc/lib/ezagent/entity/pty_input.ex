defmodule Ezagent.Entity.PtyInput do
  @moduledoc """
  Synthetic singleton Kind for PTY input dispatch — Phase 5 PR 4.

  Mirrors the RoutingAdmin pattern (Phase 4.5 PR 4): xterm.js LV hook
  calls `Ezagent.Invocation.dispatch` to `pty-input://default/behavior/pty/write`,
  which fires CapBAC step 5.5 and audit, then writes to the looked-up
  PtyServer.

  Single instance: `pty-input://default`. Spawned at boot by
  `EzagentPluginCc.Application.start`.

  Persistence `:ephemeral` — no state needed beyond the per-write
  counters in the Pty Behavior slice.
  """

  @behaviour Ezagent.Kind

  @impl Ezagent.Kind
  def type_name, do: :pty_input

  @impl Ezagent.Kind
  def behaviors, do: [Ezagent.Behavior.Pty]

  @impl Ezagent.Kind
  def persistence, do: :ephemeral

  @impl Ezagent.Kind
  def uri_from_args(args), do: Map.fetch!(args, :uri)

  @doc "The singleton URI for PTY input dispatch."
  def default_uri, do: URI.parse("pty-input://default")
end
