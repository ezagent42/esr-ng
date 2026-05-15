defmodule Esr.Kind.Runtime do
  @moduledoc """
  In-process dispatch flow inside a Kind GenServer.

  Runs Appendix A steps 5-10 once the invocation has been routed to a
  specific pid by `Esr.Invocation.dispatch/1`:

  - **5**: `BehaviorRegistry.lookup({kind_module, action})`
  - **5.5**: authz gate (Phase 1 stub — always grant + emit
    `:stub_grant` telemetry; replaced in-place at Phase 3d per
    Decision #82, hence the `PHASE-3D-STUB: DO NOT REMOVE` marker)
  - **5.7**: validate args against `behavior.interface()[action].args`
  - **6**: extract slice = `state[behavior.state_slice()]`
  - **7**: `behavior.invoke(action, slice, args, ctx)`
  - **8**: shape return into `{:ok, new_slice}` or `{:ok, new_slice, result}`
  - **9**: `put_in(state, [slice_key], new_slice)` (snapshot is Phase 3)
  - **10**: emit `[:esr, :invoke, :stop]` telemetry

  Per DECISIONS P1-D2's trade-off note: this function must be
  **defensive** about state shape because the shared `Esr.Kind.Server`
  hosts multiple Kind types whose slices may differ in shape. Phase 1
  only has Echo (map slice) so this is mostly theoretical for now —
  but the function deliberately uses `Map.get` rather than struct
  field access for forward-compat.
  """

  require Logger

  @type slice_state :: %{atom() => map()}
  @type result ::
          {:ok, slice_state(), term()}
          | {:ok, slice_state()}
          | {:error, term()}

  @spec handle_dispatch(Esr.Invocation.t(), slice_state(), module(), URI.t()) :: result()
  def handle_dispatch(
        %Esr.Invocation{target: target, args: args, ctx: ctx} = _inv,
        state,
        kind_module,
        self_uri
      ) do
    started_at = System.monotonic_time(:microsecond)

    # Phase 2: Behaviors that span multiple Kinds (e.g. Chat: Session does
    # send/join/leave, User/Agent do receive) need to branch on which Kind
    # they're currently hosting + know that Kind instance's URI for fan-out.
    # Inject both into ctx at this single point so plugins never have to
    # plumb it themselves.
    enriched_ctx =
      ctx
      |> Map.put(:kind_module, kind_module)
      |> Map.put(:self_uri, self_uri)

    with {:ok, {behavior_name_atom, action}} <- Esr.URI.behavior_action(target),
         {:ok, behavior_module} <- lookup_behavior(kind_module, action),
         :ok <- authz_stub(kind_module, behavior_module, target, enriched_ctx),
         :ok <- validate_args(behavior_module, action, args),
         slice_key <- behavior_module.state_slice(),
         slice <- Map.get(state, slice_key, %{}),
         {:ok, new_slice, result_or_nil} <-
           invoke_behavior(behavior_module, action, slice, args, enriched_ctx) do
      # Step 9 — put_in state. Snapshot wiring is Phase 1 step 3.
      new_state = Map.put(state, slice_key, new_slice)

      # Step 10 — telemetry.
      :telemetry.execute(
        [:esr, :invoke, :stop],
        %{duration_us: System.monotonic_time(:microsecond) - started_at},
        %{
          target: target,
          caller: Map.get(enriched_ctx, :caller),
          action: action,
          behavior_name: behavior_name_atom,
          behavior_module: behavior_module,
          kind_module: kind_module
        }
      )

      case result_or_nil do
        nil -> {:ok, new_state}
        result -> {:ok, new_state, result}
      end
    else
      {:error, reason} = err ->
        # Step 10 — error path also emits telemetry so audit sees it.
        :telemetry.execute(
          [:esr, :invoke, :error],
          %{duration_us: System.monotonic_time(:microsecond) - started_at},
          %{target: target, caller: Map.get(enriched_ctx, :caller), reason: reason}
        )

        err
    end
  end

  defp lookup_behavior(kind_module, action) do
    case Esr.BehaviorRegistry.lookup(kind_module, action) do
      {:ok, behavior_module} -> {:ok, behavior_module}
      :error -> {:error, {:unknown_action, action}}
    end
  end

  # PHASE-3D-STUB: DO NOT REMOVE.
  # Per Decision #82: this is the explicit permissive stub. It always
  # grants (Phase 1 has no real CapBAC) but emits `:stub_grant`
  # telemetry so the path is observable. Phase 3d replaces the body
  # with real cap matching in-place — DO NOT delete the function or
  # change its signature.
  defp authz_stub(kind_module, behavior_module, target, ctx) do
    :telemetry.execute(
      [:esr, :authz, :stub_grant],
      %{},
      %{
        kind_module: kind_module,
        behavior_module: behavior_module,
        target: target,
        caller: Map.get(ctx, :caller)
      }
    )

    :ok
  end

  defp validate_args(behavior_module, action, args) do
    interface = behavior_module.interface()

    case Map.fetch(interface, action) do
      {:ok, %{args: schema}} ->
        Esr.InterfaceValidator.validate(args, schema)

      {:ok, _action_def} ->
        # Action declared but no args schema — accept anything.
        :ok

      :error ->
        {:error, {:unknown_action, action}}
    end
  end

  defp invoke_behavior(behavior_module, action, slice, args, ctx) do
    case behavior_module.invoke(action, slice, args, ctx) do
      {:ok, new_slice} -> {:ok, new_slice, nil}
      {:ok, new_slice, result} -> {:ok, new_slice, result}
      {:error, _reason} = err -> err
    end
  catch
    kind, reason ->
      # Per Appendix A step 7 failure: caught; state untouched; DLQ
      # wiring lands in Phase 1 step 3. For now propagate the error.
      Logger.error(
        "Behavior #{inspect(behavior_module)}.invoke/#{action} crashed: " <>
          "#{inspect(kind)} #{inspect(reason)}"
      )

      {:error, {:behavior_exception, kind, reason}}
  end
end
