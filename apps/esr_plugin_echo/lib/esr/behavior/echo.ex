defmodule Esr.Behavior.Echo do
  @moduledoc """
  Echo Behavior — single action `:say` that returns the message back.

  Phase 1 Allen-can-drive flow: this is the first concrete Behavior
  that actually executes user-supplied work in dispatch path. Its
  shape (single action, `:string` arg, `:string` return) is the
  simplest possible verification of the contract.

  ## Slice shape

  ```
  %{count: integer, last_msg: nil | string}
  ```

  `count` increments each invoke. `last_msg` captures the most recent
  message — both fields exist primarily so a snapshot has meaningful
  content for Phase 3 to round-trip (Phase 1 Echo is `:ephemeral`,
  the slice updates but isn't persisted).
  """

  @behaviour Esr.Behavior

  @impl Esr.Behavior
  def actions, do: [:say]

  @impl Esr.Behavior
  def state_slice, do: :echo

  @impl Esr.Behavior
  def init_slice(_args), do: %{count: 0, last_msg: nil}

  @impl Esr.Behavior
  def invoke(:say, slice, %{msg: msg}, _ctx) when is_binary(msg) do
    new_slice = %{count: slice.count + 1, last_msg: msg}
    {:ok, new_slice, %{echo: msg}}
  end

  @impl Esr.Behavior
  def interface do
    %{
      say: %{
        args: %{msg: :string},
        returns: %{echo: :string},
        modes: [:call, :cast]
      }
    }
  end
end
