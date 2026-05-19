defmodule Ezagent.PluginCc.Template.CcAgent do
  @moduledoc """
  Unified CC agent Template Class (PR-D2, Allen 2026-05-19).

  Replaces the previous split between `cc.pty` and `cc.channel_instance`
  Template Classes. The operator now adds ONE template (`cc.agent`)
  and picks a `mode` field for how the agent is materialized:

  - `"local-pty"` — spawn a PTY-managed local `claude` process via
    erlexec (the original cc.pty behavior).
  - `"remote-channel"` — placeholder for future remote bridges
    (an external host runs `claude` and connects to ESR via the
    v2 `/cc_socket` Phoenix.Channel using a minted token). NOT
    YET IMPLEMENTED — `instantiate/3` returns `{:error,
    :remote_mode_not_implemented}`. The form option is reserved
    so the operator UI doesn't need to change later.

  ## Template data

      %{
        "class" => "cc.agent",
        "agent_uri" => "agent://cc/<name>",  # PR #131 typed shape
        "mode" => "local-pty" | "remote-channel",
        "cwd" => "/path"                     # required for local-pty
      }

  ## Idempotency (PR-D2)

  `instantiate/3` first looks up `agent_uri` in `KindRegistry`.
  If alive, returns the existing pid — no respawn, no PTY waste.
  If absent, spawns via the appropriate path. The spawned
  `PtyServer` itself registers under a `:via Registry` keyed by
  `agent_uri` so concurrent boot-time calls (e.g. multiple plugins
  each running `Workspace.Loader.load_all/0`) collapse atomically
  at the supervisor layer — `start_child` returns `{:error,
  {:already_started, pid}}` for the second-and-beyond callers.

  Pre-PR-D2 the comment said "for v1 we accept double-spawn at
  the supervisor layer" — that turned out to spawn 4× PtyServers
  per agent at boot (one per plugin re-running load_all). Fixed.
  """

  @behaviour Ezagent.Kind.Template
  @behaviour Ezagent.UI.Form

  require Logger

  @impl Ezagent.Kind.Template
  def template_name, do: "cc.agent"

  @impl Ezagent.Kind.Template
  def validate(tmpl) when is_map(tmpl) do
    with :ok <- check_class(tmpl),
         :ok <- check_agent_uri(tmpl),
         :ok <- check_mode(tmpl),
         :ok <- check_cwd_when_local(tmpl) do
      :ok
    end
  end

  def validate(_), do: {:error, :not_a_map}

  defp check_class(%{"class" => "cc.agent"}), do: :ok
  defp check_class(%{"class" => other}), do: {:error, {:wrong_class, other}}
  defp check_class(_), do: {:error, :missing_class_field}

  defp check_agent_uri(%{"agent_uri" => uri_str}) when is_binary(uri_str) and uri_str != "" do
    case URI.new(uri_str) do
      {:ok, %URI{scheme: "agent", host: "cc", path: "/" <> name}} when name != "" ->
        :ok

      {:ok, %URI{scheme: "agent", host: other, path: "/" <> _}} ->
        {:error, {:wrong_agent_type, other, expected: "cc"}}

      {:ok, %URI{scheme: "agent"}} ->
        {:error,
         {:missing_type_segment, uri_str,
          "agent URIs must be `agent://cc/<name>` (PR #131)"}}

      _ ->
        {:error, {:bad_agent_uri, uri_str}}
    end
  end

  defp check_agent_uri(_), do: {:error, :missing_agent_uri}

  defp check_mode(%{"mode" => mode}) when mode in ["local-pty", "remote-channel"], do: :ok
  defp check_mode(%{"mode" => other}), do: {:error, {:unsupported_mode, other}}
  # Back-compat: missing mode defaults to local-pty (matches pre-D2 cc.pty behavior)
  defp check_mode(tmpl) when is_map(tmpl), do: :ok

  defp check_cwd_when_local(%{"mode" => "remote-channel"}), do: :ok

  defp check_cwd_when_local(tmpl) do
    case tmpl do
      %{"cwd" => cwd} when is_binary(cwd) and cwd != "" -> :ok
      _ -> {:error, :missing_cwd}
    end
  end

  @impl Ezagent.Kind.Template
  def instantiate(_tmpl_name, %{"agent_uri" => uri_str} = tmpl, _workspace_uri) do
    agent_uri = URI.parse(uri_str)
    mode = Map.get(tmpl, "mode", "local-pty")

    # PR-D2 idempotency short-circuit: if the agent is already alive,
    # just return its URI — no spawn, no log noise. Each plugin
    # re-running Workspace.Loader.load_all/0 hits this on subsequent
    # passes (the first pass spawns, the rest no-op).
    case Ezagent.KindRegistry.lookup(agent_uri) do
      {:ok, _pid} ->
        {:ok, [agent_uri]}

      :error ->
        spawn_for_mode(mode, agent_uri, tmpl)
    end
  end

  def instantiate(_tmpl_name, tmpl, _workspace_uri), do: {:error, {:invalid_template, tmpl}}

  defp spawn_for_mode("local-pty", agent_uri, tmpl) do
    cwd = Map.fetch!(tmpl, "cwd")

    case DynamicSupervisor.start_child(
           EzagentPluginCc.PtyServerSupervisor,
           {Ezagent.PluginCc.PtyServer, %{agent_uri: agent_uri, cwd: cwd}}
         ) do
      {:ok, _pid} ->
        {:ok, [agent_uri]}

      {:error, {:already_started, _pid}} ->
        # Atomic dedup at supervisor layer (PtyServer's :via Registry
        # name made this happen). Treat as success.
        {:ok, [agent_uri]}

      {:error, reason} ->
        Logger.warning(
          "cc.agent[local-pty] spawn failed for #{URI.to_string(agent_uri)}: " <>
            inspect(reason)
        )

        {:error, reason}
    end
  end

  defp spawn_for_mode("remote-channel", agent_uri, _tmpl) do
    # Placeholder per PR-D2 plan: mint the token so a remote claude
    # can connect, but no local process is spawned. When the remote
    # connects via /cc_socket the BridgeRegistry will hold its pid;
    # KindRegistry routing into the agent uses the bridge.
    #
    # NOT WIRED YET — the spawn-or-register-virtual-Kind half of this
    # needs design. For now, return an explicit error so the operator
    # sees that "remote-channel" is a documented placeholder, not a
    # silent failure.
    Logger.info(
      "cc.agent[remote-channel] is a documented placeholder " <>
        "(uri=#{URI.to_string(agent_uri)}); returning :not_implemented"
    )

    {:error, :remote_mode_not_implemented}
  end

  # --- Ezagent.UI.Form ---------------------------------------------------------

  @impl Ezagent.UI.Form
  def form_fields do
    [
      %{
        name: "agent_uri",
        type: :uri,
        label: "Agent URI (agent://cc/<name>)",
        required: true,
        placeholder: "agent://cc/cc-architect"
      },
      %{
        name: "mode",
        type: :select,
        label: "Mode",
        required: true,
        options: ["local-pty", "remote-channel"],
        placeholder: nil
      },
      %{
        name: "cwd",
        type: :path,
        label: "Working directory (local-pty only)",
        required: false,
        placeholder: "/Users/me/Workspace/proj"
      }
    ]
  end
end
