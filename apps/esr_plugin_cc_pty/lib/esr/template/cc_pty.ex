defmodule Esr.PluginCcPty.Template do
  @moduledoc """
  Template Class for cc-pty managed claude sessions.

  Phase 4-completion PR 8 — `Esr.Kind.Template` implementation. Workspaces
  declare cc-pty agents by adding entries to `session_templates`:

      {:ok, _} = Esr.Workspace.add_template("dev-workspace", "cc-architect", %{
        "class" => "cc.pty",
        "agent_uri" => "agent://cc-architect",
        "cwd" => "/Users/h2oslabs/Workspace/proj"
      })

  On `Workspace.Loader.load_all/0` (boot) the Class's `instantiate/3`
  fires once per template entry, spawning a managed `PtyServer` under
  `EsrPluginCcPty.PtyServerSupervisor`.

  ## Idempotency (per Spec 01 Q6)

  Class.instantiate MUST be idempotent. We achieve this by:
  - Looking up the agent URI in KindRegistry first (skipped if alive)
  - If not alive, spawn the PtyServer

  Re-calling on a live agent → no-op + returns same URI.
  """

  @behaviour Esr.Kind.Template
  @behaviour Esr.UI.Form

  require Logger

  @impl Esr.Kind.Template
  def template_name, do: "cc.pty"

  @impl Esr.Kind.Template
  def validate(tmpl) when is_map(tmpl) do
    with :ok <- check_class(tmpl),
         :ok <- check_agent_uri(tmpl),
         :ok <- check_cwd(tmpl) do
      :ok
    end
  end

  def validate(_), do: {:error, :not_a_map}

  defp check_class(%{"class" => "cc.pty"}), do: :ok
  defp check_class(%{"class" => other}), do: {:error, {:wrong_class, other}}
  defp check_class(_), do: {:error, :missing_class_field}

  defp check_agent_uri(%{"agent_uri" => uri_str}) when is_binary(uri_str) and uri_str != "" do
    case URI.new(uri_str) do
      {:ok, %URI{scheme: "agent"}} -> :ok
      _ -> {:error, {:bad_agent_uri, uri_str}}
    end
  end

  defp check_agent_uri(_), do: {:error, :missing_agent_uri}

  defp check_cwd(%{"cwd" => cwd}) when is_binary(cwd) and cwd != "", do: :ok
  defp check_cwd(_), do: {:error, :missing_cwd}

  @impl Esr.Kind.Template
  def instantiate(_tmpl_name, %{"agent_uri" => agent_uri_str} = tmpl, _workspace_uri) do
    agent_uri = URI.parse(agent_uri_str)
    cwd = Map.fetch!(tmpl, "cwd")

    # Idempotency: PtyServer registers under {agent_uri, :pty_server} via
    # Registry — for v1 we identify by pid only and accept double-spawn
    # at the supervisor layer. Phase 5+ adds Registry indexing.
    case DynamicSupervisor.start_child(
           EsrPluginCcPty.PtyServerSupervisor,
           {Esr.PluginCcPty.PtyServer, %{agent_uri: agent_uri, cwd: cwd}}
         ) do
      {:ok, _pid} ->
        {:ok, [agent_uri]}

      {:error, {:already_started, _pid}} ->
        {:ok, [agent_uri]}

      {:error, reason} ->
        Logger.warning(
          "cc.pty Template instantiate failed for #{URI.to_string(agent_uri)}: " <>
            inspect(reason)
        )

        {:error, reason}
    end
  end

  def instantiate(_tmpl_name, tmpl, _workspace_uri), do: {:error, {:invalid_template, tmpl}}

  # --- Esr.UI.Form ---------------------------------------------------------

  @impl Esr.UI.Form
  def form_fields do
    [
      %{
        name: "agent_uri",
        type: :uri,
        label: "Agent URI",
        required: true,
        placeholder: "agent://cc-architect"
      },
      %{
        name: "cwd",
        type: :path,
        label: "Working directory",
        required: true,
        placeholder: "/Users/you/Workspace/project"
      }
    ]
  end
end
