defmodule Esr.Workspace.Loader do
  @moduledoc """
  Loads persisted Workspaces at app start (Phase 4c).

  ## Flow

  1. Query `Esr.Workspace.Store.list_all/0` for every persisted Workspace
  2. For each, spawn the Workspace Kind via
     `Esr.Workspace.spawn_workspace/2` so its slice carries the
     persisted members + templates + rules
  3. Dispatch `:instantiate` on the live Workspace and walk the returned
     children list, calling `Esr.SpawnRegistry.spawn/1` for each member
     URI

  ## Why this lives in esr_core (not a plugin)

  Per Phase 4 north star (plugin isolation), esr_core orchestrates the
  Workspace lifecycle but never reaches into plugin supervisors. The
  spawn fns are injected by plugins via `Esr.SpawnRegistry.register/2`,
  so the Loader stays plugin-agnostic.

  ## Timing

  Called from `EsrCore.Application.start/2` after plugins have had a
  chance to register their spawn fns. Plugin Applications **must**
  register their schemes before any Workspace declaring those schemes
  loads. We currently rely on Application start order (esr_core ⊂
  esr_plugin_chat) — chat plugin registers `agent`/`session`/`user`
  schemes in its own start callback, and at that point chat plugin
  also calls `Esr.Workspace.Loader.load_all/0` (so the Loader runs
  AFTER schemes are registered).

  Phase 5 may move this to an explicit "all plugins ready" gate.
  """

  require Logger

  alias Esr.{Invocation, SpawnRegistry, Workspace}

  @doc """
  Load every persisted Workspace and (re-)spawn each of its members.

  Returns the list of `{workspace_name, child_results}` for
  observability — each `child_results` is `[{uri, {:ok, pid}} |
  {uri, {:error, reason}}]`. Errors are logged but do not abort
  loading — a Workspace declaring an unknown scheme should produce
  a clear log but not block the rest of the boot.
  """
  @spec load_all() :: [{String.t(), [{URI.t(), term()}]}]
  def load_all do
    Workspace.Store.list_all()
    |> Enum.map(&load_one/1)
  end

  defp load_one(%{name: name} = decoded) do
    case Workspace.spawn_workspace(name, %{
           members: decoded.members,
           session_templates: decoded.session_templates,
           routing_rules: decoded.routing_rules
         }) do
      {:ok, _pid} ->
        children = instantiate_via_dispatch(decoded.uri)
        results = Enum.map(children, &spawn_child/1)
        {name, results}

      {:error, {:already_started, _pid}} ->
        # Already alive (e.g. test setup spawned it before Loader ran).
        # Dispatch :instantiate to re-spawn any missing members.
        children = instantiate_via_dispatch(decoded.uri)
        results = Enum.map(children, &spawn_child/1)
        {name, results}

      {:error, reason} ->
        Logger.warning("Workspace.Loader: failed to spawn #{name}: #{inspect(reason)}")
        {name, []}
    end
  end

  defp instantiate_via_dispatch(workspace_uri) do
    target = URI.parse("#{URI.to_string(workspace_uri)}/behavior/workspace/instantiate")

    case Invocation.dispatch(%Invocation{
           target: target,
           mode: :call,
           args: %{},
           ctx: %{
             caller: Esr.Entity.User.admin_uri(),
             caps: Esr.Entity.User.admin_caps(),
             reply: {:caller_inbox, self()}
           }
         }) do
      {:ok, %{children: children}} -> children
      other ->
        Logger.warning(
          "Workspace.Loader: instantiate dispatch returned unexpected: #{inspect(other)}"
        )

        []
    end
  end

  defp spawn_child({:member, %URI{} = uri}) do
    case SpawnRegistry.spawn(uri) do
      {:ok, pid} ->
        {uri, {:ok, pid}}

      {:error, reason} = err ->
        Logger.warning(
          "Workspace.Loader: spawn #{URI.to_string(uri)} failed: #{inspect(reason)}"
        )

        {uri, err}
    end
  end
end
