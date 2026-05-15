defmodule Esr.Kind.Server do
  @moduledoc """
  Shared GenServer that hosts every Kind instance.

  Per DECISIONS P1-D2 / Decision #84 (path B in ARCHITECTURE.md §5.7.4),
  Phase 1 uses **one** GenServer module for all Kinds. Each instance is
  parameterised by its `{kind_module, args}` pair at `start_link/1`.
  Plugin authors cannot bypass the register → subscribe → announce_ready
  lifecycle because they never write `init/1` themselves — this module
  is the only `def init/1` in the codebase (invariant #2).

  ## State shape

  ```
  %{
    kind: module(),           # the Kind module (e.g. Esr.Entity.Echo)
    uri:  URI.t(),            # this instance's URI
    state: %{atom() => map()} # per-Behavior slices, keyed by behavior.state_slice()
  }
  ```

  ## Lifecycle (Appendix A precondition)

  1. `init/1`:
     - build initial per-Behavior slices via `init_slice/1`
     - put_new into `KindRegistry` (crash on duplicate)
     - mark `:not_ready` in `ReadyGate`
     - hand off to `handle_continue(:announce_ready, ...)`
  2. `handle_continue(:announce_ready, ...)`:
     - mark `:ready` in `ReadyGate`
     - flush any buffered `:cast` invocations via `PendingDelivery.flush`
     - both pre-ready writes and the window-leak class of bugs are
       absorbed by ReadyGate + PendingDelivery (see ARCHITECTURE §5.7.4)
  3. `handle_call(:esr_dispatch, ...)` / `handle_cast(:esr_dispatch, ...)`:
     - delegate to `Esr.Kind.Runtime.handle_dispatch/3` which runs
       Appendix A steps 5-10 (BehaviorRegistry → authz stub → invoke →
       slice update → telemetry)

  ## Why `:trap_exit`

  Borrowed from old esr `Esr.Entity.Server` (SPEC borrow #4): we want
  graceful `terminate/2` so the GenServer can emit a final telemetry
  event before going down. Phase 1's terminate is a no-op pass-through;
  Phase 3 wires snapshot-on-shutdown here.
  """

  use GenServer

  @doc """
  Start a Kind instance for `{kind_module, args}`.

  `args` MUST include `:uri` (the instance URI). Other keys are
  forwarded to each Behavior's `init_slice/1`.
  """
  @spec start_link({module(), map()}) :: GenServer.on_start()
  def start_link({kind_module, args}) when is_atom(kind_module) and is_map(args) do
    GenServer.start_link(__MODULE__, {kind_module, args})
  end

  @impl true
  def init({kind_module, args}) do
    Process.flag(:trap_exit, true)

    uri = Map.fetch!(args, :uri)
    uri_str = URI.to_string(uri)

    state = %{
      kind: kind_module,
      uri: uri,
      state: build_initial_slices(kind_module, args)
    }

    case Esr.KindRegistry.put_new(uri_str, self()) do
      :ok ->
        :ok = Esr.ReadyGate.put(uri_str, :not_ready)
        {:ok, state, {:continue, :announce_ready}}

      {:error, {:already_registered, _other_pid}} ->
        # Let-it-crash — duplicate spawn is a bug at the caller layer.
        {:stop, {:already_registered, uri_str}}
    end
  end

  @impl true
  def handle_continue(:announce_ready, %{uri: uri} = state) do
    uri_str = URI.to_string(uri)
    :ok = Esr.ReadyGate.mark_ready(uri_str)

    # Drain any messages that arrived during the register→ready window.
    # They were buffered by `Esr.Invocation.dispatch/1` via PendingDelivery.
    uri_str
    |> Esr.PendingDelivery.flush()
    |> Enum.each(fn buffered_inv ->
      GenServer.cast(self(), {:esr_dispatch, buffered_inv})
    end)

    {:noreply, state}
  end

  @impl true
  def handle_call({:esr_dispatch, %Esr.Invocation{} = inv}, _from, state) do
    case Esr.Kind.Runtime.handle_dispatch(inv, state.state, state.kind) do
      {:ok, new_slice_state, result} ->
        {:reply, {:ok, result}, %{state | state: new_slice_state}}

      {:ok, new_slice_state} ->
        {:reply, :ok, %{state | state: new_slice_state}}

      {:error, _} = err ->
        {:reply, err, state}
    end
  end

  @impl true
  def handle_cast({:esr_dispatch, %Esr.Invocation{} = inv}, state) do
    case Esr.Kind.Runtime.handle_dispatch(inv, state.state, state.kind) do
      {:ok, new_slice_state, result} ->
        # cast still wants to reply via ctx.reply if set (e.g. caller_inbox).
        Esr.Invocation.reply(inv.ctx, {:ok, result})
        {:noreply, %{state | state: new_slice_state}}

      {:ok, new_slice_state} ->
        {:noreply, %{state | state: new_slice_state}}

      {:error, reason} ->
        Esr.Invocation.reply(inv.ctx, {:error, reason})
        {:noreply, state}
    end
  end

  @impl true
  def terminate(_reason, _state) do
    # Phase 1: no-op; Phase 3 wires snapshot-on-shutdown here.
    :ok
  end

  defp build_initial_slices(kind_module, args) do
    kind_module.behaviors()
    |> Enum.map(fn behavior ->
      {behavior.state_slice(), behavior.init_slice(args)}
    end)
    |> Map.new()
  end
end
