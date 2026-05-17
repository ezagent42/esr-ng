defmodule Esr.SpawnRegistry do
  @moduledoc """
  Registry mapping a URI scheme to a spawn function.

  Phase 4c: the Workspace Loader holds a list of `{:member, URI}` tuples
  (returned by `Esr.Behavior.Workspace.invoke(:instantiate, ...)`) and
  needs to bring each member URI back to life. It has no idea which
  plugin owns which Kind's supervisor — that's the **plugin isolation
  north star** at the boundary.

  Each plugin registers a spawn function for the URI schemes it owns:

      Esr.SpawnRegistry.register("agent", fn uri ->
        DynamicSupervisor.start_child(
          EsrDomainChat.AgentSupervisor,
          {Esr.Kind.Server, {Esr.Entity.Agent, %{uri: uri}}}
        )
      end)

  When the Loader sees `agent://cc-builder` it calls
  `Esr.SpawnRegistry.spawn(uri)` and esr_core never has to know about
  `EsrDomainChat.AgentSupervisor`.

  ## Idempotency

  `spawn/1` is safe to re-call for a URI that's already alive — it
  looks up `KindRegistry` first and returns `{:ok, pid}` for the
  existing process. This matters because Loader runs at app start
  and plugins may also spawn their own canonical Kinds (admin User,
  default Session).

  ## ETS layout

  `:esr_spawn_registry` set table owned by `EsrCore.EtsOwner`. Keys
  are scheme strings (e.g. `"agent"`), values are 0-arity functions
  (returning a fn waste 1 indirection but keeps the table strictly
  `{key, value}` shaped).
  """

  @table :esr_spawn_registry

  def table, do: @table

  @doc """
  Register (or overwrite) the spawn fn for a URI scheme.

  Plugins call this in their `Application.start/2`. Re-registration
  is intentional — late-binding plugins win.
  """
  @spec register(String.t(), (URI.t() -> {:ok, pid()} | {:error, term()})) :: :ok
  def register(scheme, spawn_fn) when is_binary(scheme) and is_function(spawn_fn, 1) do
    :ets.insert(@table, {scheme, spawn_fn})
    :ok
  end

  @doc """
  Spawn (or look up an existing) Kind at the given URI.

  Returns `{:ok, pid}` either way. `{:error, :no_spawn_fn}` if no
  plugin registered the URI's scheme.
  """
  @spec spawn(URI.t()) :: {:ok, pid()} | {:error, term()}
  def spawn(%URI{scheme: scheme} = uri) when is_binary(scheme) do
    case Esr.KindRegistry.lookup(uri) do
      {:ok, pid} ->
        {:ok, pid}

      :error ->
        case :ets.lookup(@table, scheme) do
          [{^scheme, fun}] ->
            case fun.(uri) do
              {:ok, pid} -> {:ok, pid}
              {:error, {:already_started, pid}} -> {:ok, pid}
              other -> other
            end

          [] ->
            {:error, {:no_spawn_fn, scheme}}
        end
    end
  end

  @doc "List registered URI schemes (for debugging / mix tasks)."
  @spec registered_schemes() :: [String.t()]
  def registered_schemes do
    :ets.tab2list(@table)
    |> Enum.map(fn {scheme, _fn} -> scheme end)
    |> Enum.sort()
  end
end
