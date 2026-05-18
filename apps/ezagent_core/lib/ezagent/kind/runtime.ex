defmodule Ezagent.Kind.Runtime do
  @moduledoc """
  In-process dispatch flow inside a Kind GenServer.

  Runs Appendix A steps 5-10 once the invocation has been routed to a
  specific pid by `Ezagent.Invocation.dispatch/1`:

  - **5**: `BehaviorRegistry.lookup({kind_module, action})`
  - **5.5**: authz gate — `Ezagent.Capability.matches?` against ctx.caps
    (Phase 3d hard flip per P3-D6). Emits `[:ezagent, :authz, :granted]`
    or `[:ezagent, :authz, :denied]`. The Phase 1-2 permissive stub
    (emit `:stub_grant` + always grant) is GONE; check_invariants #9
    enforces the atom no longer appears in code.
  - **5.7**: validate args against `behavior.interface()[action].args`
  - **6**: extract slice = `state[behavior.state_slice()]`
  - **7**: `behavior.invoke(action, slice, args, ctx)`
  - **8**: shape return into `{:ok, new_slice}` or `{:ok, new_slice, result}`
  - **9**: `put_in(state, [slice_key], new_slice)` (snapshot is Phase 3)
  - **10**: emit `[:ezagent, :invoke, :stop]` telemetry

  Per DECISIONS P1-D2's trade-off note: this function must be
  **defensive** about state shape because the shared `Ezagent.Kind.Server`
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

  @spec handle_dispatch(Ezagent.Invocation.t(), slice_state(), module(), URI.t()) :: result()
  def handle_dispatch(
        %Ezagent.Invocation{target: target, args: args, ctx: ctx} = _inv,
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
    #
    # Phase 7 PR 43 (D7-3): also inject `:session_uri` derived from the
    # target URI. This is what `Ezagent.Capability.instance_match?/2`
    # consumes when evaluating a `{:within_session, S}` scope-tuple
    # cap shape (Decision #137). Without this enrichment, CapBAC has
    # no way to know which session a dispatch is happening in, so
    # scope-bounded delegation can't be enforced. Derivation is pure
    # URI parsing — no dispatch, no registry lookup, O(1).
    enriched_ctx =
      ctx
      |> Map.put(:kind_module, kind_module)
      |> Map.put(:self_uri, self_uri)
      |> Map.put(:session_uri, derive_session_uri(target))

    with {:ok, {behavior_name_atom, action}} <- Ezagent.URI.behavior_action(target),
         {:ok, behavior_module} <- lookup_behavior(kind_module, action),
         :ok <- authz_check(kind_module, action, target, enriched_ctx),
         :ok <- validate_args(behavior_module, action, args),
         slice_key <- behavior_module.state_slice(),
         slice <- Map.get(state, slice_key, %{}),
         {:ok, new_slice, result_or_nil} <-
           invoke_behavior(behavior_module, action, slice, args, enriched_ctx) do
      # Step 9 — put_in state. Snapshot wiring is Phase 1 step 3.
      new_state = Map.put(state, slice_key, new_slice)

      # Step 10 — telemetry.
      :telemetry.execute(
        [:ezagent, :invoke, :stop],
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
          [:ezagent, :invoke, :error],
          %{duration_us: System.monotonic_time(:microsecond) - started_at},
          %{target: target, caller: Map.get(enriched_ctx, :caller), reason: reason}
        )

        err
    end
  end

  defp lookup_behavior(kind_module, action) do
    case Ezagent.BehaviorRegistry.lookup(kind_module, action) do
      {:ok, behavior_module} -> {:ok, behavior_module}
      :error -> {:error, {:unknown_action, action}}
    end
  end

  # Phase 3d hard flip (per P3-D6): real cap check via Capability.matches?.
  # `:stub_grant` telemetry is GONE — replaced with `:granted` (success)
  # and `:denied` (failure). Per memory feedback_let_it_crash_no_workarounds:
  # no feature flag, no parallel paths; the alarm path is "this function
  # ever emits :stub_grant" which check_invariants #9 enforces.
  defp authz_check(kind_module, action, target, ctx) do
    needed = Ezagent.Capability.cap_for_action(kind_module, action, target)
    caps = Map.get(ctx, :caps, MapSet.new())

    granted? =
      Enum.any?(caps, fn cap ->
        Ezagent.Capability.matches?(cap, needed)
      end)

    meta = %{
      kind_module: kind_module,
      action: action,
      target: target,
      caller: Map.get(ctx, :caller),
      needed: needed
    }

    if granted? do
      :telemetry.execute([:ezagent, :authz, :granted], %{}, meta)
      :ok
    else
      :telemetry.execute([:ezagent, :authz, :denied], %{}, meta)
      {:error, :unauthorized}
    end
  end

  defp validate_args(behavior_module, action, args) do
    interface = behavior_module.interface()

    case Map.fetch(interface, action) do
      {:ok, %{args: schema}} ->
        Ezagent.InterfaceValidator.validate(args, schema)

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

  # Phase 7 PR 43 — derive session URI from target URI for ctx enrichment.
  #
  # Sources covered:
  # - `session://main/behavior/chat/send` → `session://main`
  # - `session://main` → `session://main` (already session)
  # - `agent://cc-demo/behavior/chat/receive` → nil (not session-targeted)
  # - any non-session URI → nil
  #
  # Pure URI manipulation; no registry / dispatch / GenServer involvement.
  # Returning `nil` for non-session targets is correct — a cap with
  # `{:within_session, S}` shape should not match when the dispatch
  # isn't even session-scoped, and `Capability.instance_match?/2` is
  # designed to handle nil session_uri (returns false for the tuple
  # case, preserving deny-as-default).
  defp derive_session_uri(%URI{scheme: "session", host: host} = target)
       when is_binary(host) do
    %URI{scheme: "session", host: host, authority: host}
  end

  defp derive_session_uri(_other), do: nil
end
