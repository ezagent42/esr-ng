defmodule Ezagent.Entity.Echo do
  @moduledoc """
  Echo Kind — instance type for the Phase 1 demo flow.

  `entity://agent/default/echo_default` is the default instance spawned by
  `EzagentPluginEcho.Application.start/2` (PR #141 SPEC v2 — flavor
  prefix on name). Composing only the Echo Behavior, it's the
  smallest possible Kind that exercises dispatch + audit +
  (eventually) LiveView render.
  """

  @behaviour Ezagent.Kind

  @impl Ezagent.Kind
  def type_name, do: :echo

  @impl Ezagent.Kind
  def behaviors, do: [Ezagent.Behavior.Echo]

  @impl Ezagent.Kind
  def persistence, do: :ephemeral
end
