defmodule Ezagent.Template.CcChannelInstance do
  @moduledoc """
  Phase 5 PR 5 — Template Class for registering a CC channel instance.

  ## Template data

      %{
        "class" => "cc.channel_instance",
        "agent_uri" => "agent://cc-architect"  # required
      }

  ## instantiate/3

  Mints (or reuses) a connect token for `agent_uri`, persists it via
  `EzagentPluginCc.TokenStore`, registers the agent_uri ↔ token
  mapping. CC instances later authenticate by presenting the token on
  the announce path (PR 5b will wire that into the v1 announce
  controller's token check).

  Returns `{:ok, [agent_uri]}` — the registered URI is what shows up
  in the Workspace's session_templates list.

  Idempotent: re-instantiating returns the same token.
  """

  @behaviour Ezagent.Kind.Template
  @behaviour Ezagent.UI.Form

  require Logger

  @impl Ezagent.Kind.Template
  def template_name, do: "cc.channel_instance"

  @impl Ezagent.Kind.Template
  def validate(%{"class" => "cc.channel_instance", "agent_uri" => uri_str})
      when is_binary(uri_str) and uri_str != "" do
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

  def validate(%{"class" => "cc.channel_instance"}), do: {:error, :missing_agent_uri}
  def validate(%{"class" => other}), do: {:error, {:wrong_class, other}}
  def validate(_), do: {:error, :missing_class}

  @impl Ezagent.Kind.Template
  def instantiate(_tmpl_name, %{"agent_uri" => uri_str}, _workspace_uri) do
    agent_uri = URI.parse(uri_str)

    case EzagentPluginCc.TokenStore.mint(agent_uri) do
      {:ok, token} ->
        Logger.info(
          "cc.channel_instance: registered #{uri_str} with token #{String.slice(token, 0..14)}…"
        )

        {:ok, [agent_uri]}

      err ->
        Logger.error("cc.channel_instance: token mint failed: #{inspect(err)}")
        err
    end
  end

  # --- Ezagent.UI.Form --------------------------------------------------------

  @impl Ezagent.UI.Form
  def form_fields do
    [
      %{
        name: "agent_uri",
        type: :uri,
        label: "Agent URI (PR #131: must be agent://cc/<name>)",
        required: true,
        placeholder: "agent://cc/remote-mac-claude"
      }
    ]
  end
end
