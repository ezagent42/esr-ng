defmodule Ezagent.Workspace.Loader do
  @moduledoc """
  Loads persisted Workspaces at app start (Phase 4c).

  ## Flow

  1. Query `Ezagent.Workspace.Store.list_all/0` for every persisted Workspace
  2. For each, spawn the Workspace Kind via
     `Ezagent.Workspace.spawn_workspace/2` so its slice carries the
     persisted members + templates + rules
  3. Dispatch `:instantiate` on the live Workspace and walk the returned
     children list, calling `Ezagent.SpawnRegistry.spawn/1` for each member
     URI

  ## Why this lives in ezagent_core (not a plugin)

  Per Phase 4 north star (plugin isolation), ezagent_core orchestrates the
  Workspace lifecycle but never reaches into plugin supervisors. The
  spawn fns are injected by plugins via `Ezagent.SpawnRegistry.register/2`,
  so the Loader stays plugin-agnostic.

  ## Timing

  Called from `EzagentCore.Application.start/2` after plugins have had a
  chance to register their spawn fns. Plugin Applications **must**
  register their schemes before any Workspace declaring those schemes
  loads. We currently rely on Application start order (ezagent_core ⊂
  ezagent_domain_chat) — chat plugin registers `agent`/`session`/`user`
  schemes in its own start callback, and at that point chat plugin
  also calls `Ezagent.Workspace.Loader.load_all/0` (so the Loader runs
  AFTER schemes are registered).

  Phase 5 may move this to an explicit "all plugins ready" gate.
  """

  require Logger

  alias Ezagent.{Invocation, SpawnRegistry, TemplateRegistry, Workspace}

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
    # Phase 5 PR 6: defensive — when multiple plugin Applications all
    # call load_all/0 at boot (Decision #112 pattern), the Repo's
    # sandbox pool can saturate in test env. A boot-time DB unavailable
    # state shouldn't crash the whole umbrella — log and return [].
    # The plugin's later Loader.load_all runs catch up; tests checkout
    # connections explicitly per Sandbox docs.
    try do
      Workspace.Store.list_all() |> Enum.map(&load_one/1)
    rescue
      e in [DBConnection.ConnectionError, DBConnection.OwnershipError] ->
        Logger.warning(
          "Workspace.Loader.load_all: DB unavailable at boot (#{inspect(e.__struct__)}); " <>
            "skipping — plugin re-runs or per-test setup will pick up Workspaces"
        )

        []
    end
  end

  defp load_one(%{name: name} = decoded) do
    case Workspace.spawn_workspace(name, %{
           members: decoded.members,
           session_templates: decoded.session_templates,
           routing_rules: decoded.routing_rules
         }) do
      {:ok, _pid} ->
        children = instantiate_via_dispatch(decoded.uri)
        results = Enum.map(children, &spawn_child(&1, decoded.uri))
        {name, results}

      {:error, {:already_started, _pid}} ->
        # Already alive (e.g. test setup spawned it before Loader ran).
        # Dispatch :instantiate to re-spawn any missing members.
        children = instantiate_via_dispatch(decoded.uri)
        results = Enum.map(children, &spawn_child(&1, decoded.uri))
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
             caller: Ezagent.Entity.User.admin_uri(),
             caps: Ezagent.Entity.User.admin_caps(),
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

  defp spawn_child({:member, %URI{} = uri}, _workspace_uri) do
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

  defp spawn_child({:template, tmpl_name, tmpl_data}, workspace_uri) do
    case extract_class_name(tmpl_data) do
      nil ->
        Logger.warning(
          "Workspace.Loader: template #{inspect(tmpl_name)} missing \"class\" field in " <>
            "workspace #{URI.to_string(workspace_uri)}, skipping"
        )

        {tmpl_name, {:error, :missing_class_field}}

      class_name ->
        case TemplateRegistry.lookup(class_name) do
          {:ok, class_module} ->
            invoke_template(class_module, tmpl_name, tmpl_data, workspace_uri)

          :error ->
            Logger.warning(
              "Workspace.Loader: no Template Class registered for " <>
                "#{inspect(class_name)} (template #{inspect(tmpl_name)}) in workspace " <>
                "#{URI.to_string(workspace_uri)}, skipping"
            )

            {tmpl_name, {:error, {:no_template_class, class_name}}}
        end
    end
  end

  defp invoke_template(class_module, tmpl_name, tmpl_data, workspace_uri) do
    case class_module.instantiate(tmpl_name, tmpl_data, workspace_uri) do
      {:ok, uris} when is_list(uris) ->
        # Phase 7 PR 31 (IMPL-7-1): bind every session URI the
        # Template Class spawned to this workspace, so production
        # dispatch via Ezagent.Behavior.Chat.invoke(:send) can resolve
        # workspace_uri for the Resolver call (chat.ex:116).
        # Non-session URIs are bound too — harmless, and avoids
        # special-casing scheme detection in this fan-out path.
        Enum.each(uris, fn uri ->
          Ezagent.WorkspaceRegistry.bind(uri, workspace_uri)
        end)

        {tmpl_name, {:ok, uris}}

      {:error, reason} = err ->
        Logger.warning(
          "Workspace.Loader: template #{inspect(tmpl_name)} instantiate returned " <>
            "#{inspect(reason)} in workspace #{URI.to_string(workspace_uri)}"
        )

        {tmpl_name, err}

      other ->
        Logger.warning(
          "Workspace.Loader: template #{inspect(tmpl_name)} returned unexpected " <>
            "#{inspect(other)} (expected `{:ok, [URI]}` or `{:error, _}`)"
        )

        {tmpl_name, {:error, {:bad_template_return, other}}}
    end
  end

  defp extract_class_name(%{"class" => name}) when is_binary(name) and name != "", do: name
  defp extract_class_name(%{class: name}) when is_binary(name) and name != "", do: name
  defp extract_class_name(_), do: nil
end
