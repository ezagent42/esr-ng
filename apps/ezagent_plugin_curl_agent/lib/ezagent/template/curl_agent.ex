defmodule Ezagent.PluginCurlAgent.Template do
  @moduledoc """
  Template Class `curl.agent` — declares a CurlAgent instance in a
  Workspace.

  Form fields (auto-derived UI via `Ezagent.UI.Form`):

  - `agent_uri` — `curl-agent://<name>` (the instance URI)
  - `provider` — `"deepseek"` / `"openai"` / ... (matches the key
    provider stored on the owner User's `api_keys` slice)
  - `api_url` — full URL of the OpenAI-compatible
    `/chat/completions` endpoint
  - `model` — provider-specific model id
  - `system_prompt` — optional textarea
  - `max_history` — int, default 20
  - `owner_uri` — `user://<uri>` whose api_key the agent uses
    (admin can set; LV pre-fills to caller_uri)

  ## On instantiate

  Spawns the CurlAgent Kind at `curl-agent://<name>` with the
  config as `init_slice` args. Idempotent against KindRegistry —
  re-instantiate skips if already alive.

  ## What this template does NOT validate

  - Whether the owner User has a `provider` key set today —
    `:receive` will surface a chat-visible error at the first
    message if the key is missing. This matches the cc.pty
    pattern: instantiate-time validation only covers structural
    correctness; runtime errors are surfaced via the chat itself.
  """

  @behaviour Ezagent.Kind.Template
  @behaviour Ezagent.UI.Form

  require Logger

  @impl Ezagent.Kind.Template
  def template_name, do: "curl.agent"

  @impl Ezagent.Kind.Template
  def validate(tmpl) when is_map(tmpl) do
    with :ok <- check_class(tmpl),
         :ok <- check_agent_uri(tmpl),
         :ok <- check_provider(tmpl),
         :ok <- check_api_url(tmpl),
         :ok <- check_model(tmpl) do
      :ok
    end
  end

  def validate(_), do: {:error, :not_a_map}

  defp check_class(%{"class" => "curl.agent"}), do: :ok
  defp check_class(%{"class" => other}), do: {:error, {:wrong_class, other}}
  defp check_class(_), do: {:error, :missing_class_field}

  # PR #131 (Allen 2026-05-19): strict `agent://curl/<name>` shape.
  # The legacy `curl-agent://` scheme and the un-typed `agent://<name>`
  # form are both rejected — operators must migrate to the new
  # format (DB migration does this for the existing demo workspaces).
  defp check_agent_uri(%{"agent_uri" => uri_str}) when is_binary(uri_str) and uri_str != "" do
    case URI.new(uri_str) do
      {:ok, %URI{scheme: "agent", host: "curl", path: "/" <> name}} when name != "" ->
        :ok

      {:ok, %URI{scheme: "agent", host: other, path: "/" <> _}} ->
        {:error, {:wrong_agent_type, other, expected: "curl"}}

      {:ok, %URI{scheme: "agent"}} ->
        {:error,
         {:missing_type_segment, uri_str,
          "agent URIs must be `agent://curl/<name>` (PR #131)"}}

      _ ->
        {:error, {:bad_agent_uri, uri_str}}
    end
  end

  defp check_agent_uri(_), do: {:error, :missing_agent_uri}

  defp check_provider(%{"provider" => p}) when is_binary(p) and p != "", do: :ok
  defp check_provider(_), do: {:error, :missing_provider}

  defp check_api_url(%{"api_url" => u}) when is_binary(u) and u != "" do
    if String.starts_with?(u, "http://") or String.starts_with?(u, "https://") do
      :ok
    else
      {:error, {:bad_api_url, u}}
    end
  end

  defp check_api_url(_), do: {:error, :missing_api_url}

  defp check_model(%{"model" => m}) when is_binary(m) and m != "", do: :ok
  defp check_model(_), do: {:error, :missing_model}

  @impl Ezagent.Kind.Template
  def instantiate(_tmpl_name, %{"agent_uri" => agent_uri_str} = tmpl, _workspace_uri) do
    agent_uri = URI.parse(agent_uri_str)

    init_args = %{
      uri: agent_uri,
      provider: tmpl["provider"],
      api_url: tmpl["api_url"],
      model: tmpl["model"],
      system_prompt: nil_if_empty(tmpl["system_prompt"]),
      max_history: parse_int(tmpl["max_history"], 20),
      owner_uri: parse_owner_uri(tmpl["owner_uri"])
    }

    case DynamicSupervisor.start_child(
           EzagentPluginCurlAgent.InstanceSupervisor,
           {Ezagent.Kind.Server, {Ezagent.Entity.CurlAgent, init_args}}
         ) do
      {:ok, _pid} ->
        {:ok, [agent_uri]}

      {:error, {:already_started, _pid}} ->
        {:ok, [agent_uri]}

      {:error, reason} ->
        Logger.warning(
          "curl.agent Template instantiate failed for #{URI.to_string(agent_uri)}: " <>
            inspect(reason)
        )

        {:error, reason}
    end
  end

  def instantiate(_tmpl_name, tmpl, _workspace_uri), do: {:error, {:invalid_template, tmpl}}

  defp nil_if_empty(nil), do: nil
  defp nil_if_empty(""), do: nil
  defp nil_if_empty(s) when is_binary(s), do: s

  defp parse_int(nil, default), do: default
  defp parse_int(n, _) when is_integer(n) and n > 0, do: n

  defp parse_int(s, default) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} when n > 0 -> n
      _ -> default
    end
  end

  defp parse_int(_, default), do: default

  defp parse_owner_uri(nil), do: URI.parse("user://admin")
  defp parse_owner_uri(""), do: URI.parse("user://admin")

  defp parse_owner_uri(s) when is_binary(s) do
    case URI.new(s) do
      {:ok, %URI{scheme: "user"} = u} -> u
      _ -> URI.parse("user://admin")
    end
  end

  # --- Ezagent.UI.Form ---------------------------------------------------

  @impl Ezagent.UI.Form
  def form_fields do
    [
      %{
        name: "agent_uri",
        type: :uri,
        label: "Agent URI (use agent:// so it shows in mention/floating dropdowns)",
        required: true,
        placeholder: "agent://curl/my-deepseek"
      },
      %{
        name: "provider",
        type: :text,
        label: "Provider (selects which api_keys entry to use)",
        required: true,
        placeholder: "deepseek"
      },
      %{
        name: "api_url",
        type: :text,
        label: "API URL (OpenAI-compatible /chat/completions endpoint)",
        required: true,
        placeholder: "https://api.deepseek.com/chat/completions"
      },
      %{
        name: "model",
        type: :text,
        label: "Model",
        required: true,
        placeholder: "deepseek-chat"
      },
      %{
        name: "system_prompt",
        type: :text,
        label: "System prompt (optional)",
        required: false,
        placeholder: "You are a concise, helpful assistant."
      },
      %{
        name: "max_history",
        type: :text,
        label: "Max history turns",
        required: false,
        placeholder: "20"
      },
      %{
        name: "owner_uri",
        type: :uri,
        label: "Owner user URI (whose api_key gets used)",
        required: false,
        placeholder: "user://admin"
      }
    ]
  end
end
