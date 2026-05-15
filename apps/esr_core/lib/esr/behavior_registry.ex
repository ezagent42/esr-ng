defmodule Esr.BehaviorRegistry do
  @moduledoc """
  BehaviorRegistry — `{kind_module, action_atom}` → behavior_module.

  Resolves which `Esr.Behavior` implementation handles a given Kind +
  action pair during `Esr.Invocation.dispatch/1`. Bare ETS (not stdlib
  Registry) because the key shape is a tuple and we don't need
  process monitoring.

  Owned by `EsrCore.EtsOwner`. Phase 1 step 4 (Echo plugin
  Application.start/2) calls `register/3` to wire `{Esr.Entity.Echo,
  :say} → Esr.Behavior.Echo`.

  ## Phase 1 scope

  Registration is one-shot at app boot. Phase 2+ may add dynamic
  registration paths (hot-loading plugins) — defer until needed.
  """

  @table :esr_behavior_registry

  def table, do: @table

  @doc """
  Register `{kind, action} → behavior`. Overwrites if already present
  (last-writer-wins is fine for boot-time wiring).
  """
  @spec register(kind :: module(), action :: atom(), behavior :: module()) :: :ok
  def register(kind, action, behavior)
      when is_atom(kind) and is_atom(action) and is_atom(behavior) do
    :ets.insert(@table, {{kind, action}, behavior})
    :ok
  end

  @doc """
  Look up the behavior module for `{kind, action}`.

  Returns `{:ok, behavior_module}` or `:error`. Dispatch treats
  `:error` as "zero-match" → DLQ unroutable per invariant #7.
  """
  @spec lookup(kind :: module(), action :: atom()) :: {:ok, module()} | :error
  def lookup(kind, action) when is_atom(kind) and is_atom(action) do
    case :ets.lookup(@table, {kind, action}) do
      [{_, behavior}] -> {:ok, behavior}
      [] -> :error
    end
  end

  @doc "List all `{{kind, action}, behavior}` triples — for debug/admin."
  @spec list_all() :: [{{module(), atom()}, module()}]
  def list_all, do: :ets.tab2list(@table)
end
