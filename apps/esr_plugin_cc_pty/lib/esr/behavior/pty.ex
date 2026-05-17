defmodule Esr.Behavior.Pty do
  @moduledoc """
  Phase 5 PR 4 — Behavior providing `:write` action for the synthetic
  `pty-input://default` Kind.

  ## Why synthetic singleton (like RoutingAdmin from Phase 4.5 PR 4)

  PtyServer GenServers aren't Kind Servers — they're just DynamicSupervisor
  children. Making each PtyServer a Kind Server would be a much larger
  change. Instead, mimic the RoutingAdmin pattern (Phase 4.5 PR 4
  Decision #125): introduce `Esr.Entity.PtyInput` synthetic singleton at
  `pty-input://default`; xterm.js LV hook calls
  `Esr.Invocation.dispatch` targeting
  `pty-input://default/behavior/pty/write` with `args: %{agent_uri, bytes}`.

  This satisfies the **critical invariant** (IMPLEMENTATION_ROADMAP §1.3 #1):
  PTY input goes through `Esr.Invocation.dispatch` → CapBAC step 5.5 →
  audit telemetry → PtyServer write. The xterm hook never touches the
  PtyServer directly or pushes raw PubSub.

  `agents_pty_input_dispatch_test.exs` is the regression gate.

  ## Cap shape

  - `kind: :pty_input`
  - `behavior: Esr.Behavior.Pty`
  - `instance: pty-input://default`

  Admin's triple-`:any` passes. Grant explicitly for non-admin users.
  """

  @behaviour Esr.Behavior

  @impl Esr.Behavior
  def actions, do: [:write]

  @impl Esr.Behavior
  def state_slice, do: :pty_input

  @impl Esr.Behavior
  def init_slice(_args), do: %{write_calls: 0, total_bytes: 0}

  @impl Esr.Behavior
  def invoke(:write, slice, %{agent_uri: agent_uri_str, bytes: bytes}, _ctx)
      when is_binary(agent_uri_str) and is_binary(bytes) do
    agent_uri = URI.parse(agent_uri_str)

    case Esr.PluginCcPty.PtyServer.find_by_agent_uri(agent_uri) do
      {:ok, pid} ->
        case Esr.PluginCcPty.PtyServer.write_input(pid, bytes) do
          :ok ->
            new_slice = %{
              slice
              | write_calls: slice.write_calls + 1,
                total_bytes: slice.total_bytes + byte_size(bytes)
            }

            {:ok, new_slice, %{bytes_written: byte_size(bytes)}}

          err ->
            err
        end

      :error ->
        {:error, :no_pty_server}
    end
  end

  def invoke(:write, _slice, _args, _ctx),
    do: {:error, {:invalid_args, :agent_uri_and_bytes_required}}

  @impl Esr.Behavior
  def interface do
    %{
      write: %{
        args: %{agent_uri: :string, bytes: :string},
        returns: %{bytes_written: :integer},
        modes: [:call, :cast]
      }
    }
  end

  @doc "Cap-needed shape — used by Identity.grant operations."
  def required_cap_shape do
    %{
      kind: :pty_input,
      behavior: __MODULE__,
      instance: Esr.Entity.PtyInput.default_uri()
    }
  end
end
