defmodule Esr.Invocation do
  @moduledoc """
  Invocation — the universal request shape.

  Per ARCHITECTURE.md §4.2 + Appendix A. Adapters construct
  `%Esr.Invocation{}` from external protocol events, then call
  `dispatch/1`; the dispatch path is shared regardless of adapter.

  ## 12-step dispatch flow (Appendix A)

  Phase 1 implementation splits the 12 steps between this module
  (steps 1-4, 11-12) and `Esr.Kind.Runtime` (steps 5-10, inside the
  Kind GenServer). Validation (step 2.5) moves to step 5.5 because
  it needs the Behavior's `@interface` which is found in step 5.

  ## Reply table

  `reply/2` routes a result back to the caller per `ctx.reply` (7
  cases per §4.3). Phase 1 implements `:caller_inbox`, `:phoenix_pubsub`,
  `:ignore` — the protocol-bound cases (`:plug_conn`, `:phoenix_channel`,
  `:stdio_pipe`, `:mcp_response`) raise on use until their adapter
  arrives in later phases.
  """

  @type mode :: :call | :cast | :call_stream | :subscribe | :introspect

  @type reply_target ::
          {:phoenix_channel, topic :: String.t()}
          | {:phoenix_pubsub, topic :: String.t()}
          | {:plug_conn, conn :: term()}
          | {:stdio_pipe, pid :: port()}
          | {:mcp_response, request_id :: String.t()}
          | {:caller_inbox, pid :: pid()}
          | :ignore

  @type ctx :: %{
          required(:caller) => URI.t(),
          required(:caps) => MapSet.t(Esr.Capability.t()),
          required(:reply) => reply_target(),
          optional(:trace_id) => String.t(),
          optional(:deadline_ms) => pos_integer(),
          optional(:idempotency_key) => String.t()
        }

  @enforce_keys [:target, :mode, :args, :ctx]
  defstruct [:target, :mode, :args, :ctx]

  @type t :: %__MODULE__{
          target: URI.t(),
          mode: mode(),
          args: map(),
          ctx: ctx()
        }

  # --- dispatch ----------------------------------------------------------

  @doc """
  Dispatch this invocation. See Appendix A for the 12-step flow.

  Phase 1 simplifications:
  - Args validation (step 2.5) is deferred into the Kind.Runtime path
    after BehaviorRegistry lookup gives us the `@interface`
  - `:subscribe` and `:introspect` modes are not yet implemented;
    they return `{:error, :unsupported_mode}` until Phase 2+
  """
  @spec dispatch(t()) ::
          {:ok, term()}
          | :ok
          | {:error, :no_such_actor}
          | {:error, :not_ready}
          | {:error, :unsupported_mode}
          | {:error, {:invalid_args, list()}}
          | {:error, {:unknown_action, atom()}}
          | {:error, :unauthorized}
          | {:ok, :duplicate_ignored}
  def dispatch(%__MODULE__{mode: mode}) when mode in [:subscribe, :introspect] do
    {:error, :unsupported_mode}
  end

  def dispatch(%__MODULE__{target: target, mode: mode, ctx: ctx} = inv) do
    instance_uri = Esr.URI.instance(target)

    with :ok <- maybe_idempotency_check(ctx) do
      case {Esr.ReadyGate.status(instance_uri), mode} do
        {:ready, _} ->
          deliver_to_ready(instance_uri, mode, inv)

        {:not_ready, :cast} ->
          # Buffer for delivery once instance announces ready.
          Esr.PendingDelivery.buffer(instance_uri, inv)
          :ok

        {:not_ready, m} when m in [:call, :call_stream] ->
          # Invariant #3: :call to not-ready fail-fast (caller's
          # synchronous block would otherwise hit deadline_ms).
          {:error, :not_ready}

        {:unknown, _} ->
          {:error, :no_such_actor}
      end
    end
  end

  defp deliver_to_ready(instance_uri, :cast, inv) do
    case Esr.KindRegistry.lookup(instance_uri) do
      {:ok, pid} ->
        GenServer.cast(pid, {:esr_dispatch, inv})
        :ok

      :error ->
        {:error, :no_such_actor}
    end
  end

  defp deliver_to_ready(instance_uri, mode, inv) when mode in [:call, :call_stream] do
    case Esr.KindRegistry.lookup(instance_uri) do
      {:ok, pid} ->
        timeout = inv.ctx[:deadline_ms] || 5_000
        GenServer.call(pid, {:esr_dispatch, inv}, timeout)

      :error ->
        {:error, :no_such_actor}
    end
  end

  defp maybe_idempotency_check(%{idempotency_key: key}) when is_binary(key) do
    if Esr.Idempotency.seen?(key) do
      {:ok, :duplicate_ignored}
    else
      :ok = Esr.Idempotency.record(key)
      :ok
    end
  end

  defp maybe_idempotency_check(_ctx), do: :ok

  # --- reply -------------------------------------------------------------

  @doc """
  Route a result back to the caller per `ctx.reply`.

  Phase 1 cases:
  - `{:caller_inbox, pid}` — `send(pid, {:esr_reply, result})`
  - `{:phoenix_pubsub, topic}` — `Phoenix.PubSub.broadcast(EsrCore.PubSub,
    topic, {:esr_reply, result})` — allowed only for view fan-out topics
    (§5.7.6); audit:stream is the canonical example
  - `:ignore` — no-op (silent success)

  Later phases (`:phoenix_channel`, `:plug_conn`, `:stdio_pipe`,
  `:mcp_response`) raise `ArgumentError` for now.
  """
  @spec reply(ctx(), term()) :: :ok | no_return()
  def reply(%{reply: {:caller_inbox, pid}}, result) when is_pid(pid) do
    send(pid, {:esr_reply, result})
    :ok
  end

  def reply(%{reply: {:phoenix_pubsub, topic}}, result) when is_binary(topic) do
    Phoenix.PubSub.broadcast(EsrCore.PubSub, topic, {:esr_reply, result})
    :ok
  end

  def reply(%{reply: :ignore}, _result), do: :ok

  def reply(%{reply: {kind, _}}, _result)
      when kind in [:phoenix_channel, :plug_conn, :stdio_pipe, :mcp_response] do
    raise ArgumentError,
          "reply target #{inspect(kind)} not yet implemented in Phase 1 — arrives with its adapter"
  end
end
