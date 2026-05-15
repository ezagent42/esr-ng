defmodule Esr.Entity.Echo do
  @moduledoc """
  Echo Kind — instance type for the Phase 1 demo flow.

  `agent://echo` is the default instance spawned by
  `EsrPluginEcho.Application.start/2`. Composing only the Echo
  Behavior, it's the smallest possible Kind that exercises dispatch +
  audit + (eventually) LiveView render.
  """

  @behaviour Esr.Kind

  @impl Esr.Kind
  def type_name, do: :echo

  @impl Esr.Kind
  def behaviors, do: [Esr.Behavior.Echo]

  @impl Esr.Kind
  def persistence, do: :ephemeral
end
