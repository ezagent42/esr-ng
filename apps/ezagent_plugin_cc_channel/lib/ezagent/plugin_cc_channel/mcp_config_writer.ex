defmodule EzagentPluginCcChannel.McpConfigWriter do
  @moduledoc """
  Writes the `.mcp.json` Claude Code consumes via `--mcp-config` for
  the v2 CC channel bridge.

  Replaces `Ezagent.Bridge.V1Prototype.McpConfigWriter` (HTTP/SSE wire)
  with a v2-shaped config that points Claude at the WebSocket Python
  client script + injects the WS URL, agent URI, and per-instance
  connect token.

  ## Output

  - **Primary:** `~/.ezagent/bridge.mcp.json` (configurable
    via `Application.get_env(:ezagent_plugin_cc_channel, :mcp_config_dir)`).
  - **Project root copy:** `<git toplevel>/.mcp.json` — Claude's
    `--dangerously-load-development-channels` flag looks up the server
    name in project/user MCP configs **before** reading
    `--mcp-config <abs>`. Without the project-level file, Claude
    prints `server:esr-bridge · no MCP server configured`. The
    project-level copy suppresses that warning; `--mcp-config <abs>`
    remains for explicit pathing.

  ## Why a token

  v1 had no auth — any process that could reach the HTTP port could
  announce as any agent_uri. v2 gates the WS join via
  `EzagentPluginCcChannel.TokenStore`. `write!/1` mints (idempotent) a
  token for `agent_uri` and bakes it into the mcp.json env block so
  the Python bridge can present it on join.

  ## Decision #131 preservation

  PtyServer (`apps/ezagent_plugin_cc_pty/lib/esr/plugin_cc_pty/pty_server.ex`)
  passes `agent_uri: URI.to_string(state.agent_uri)` when calling this
  writer — the URI is known at spawn time, so it rides in mcp.json
  deterministically instead of leaking via the operator's shell env.
  """

  alias EzagentPluginCcChannel.TokenStore

  @default_dir Path.expand("~/.ezagent")
  @config_filename "bridge.mcp.json"

  @doc """
  Write the v2 bridge mcp.json. Returns `{:ok, abs_path}`.

  Required opt:
  - `:agent_uri` — string. Used both as the WS join target and the
    TokenStore key.

  Optional opts:
  - `:dir` — override output directory.
  - `:script_path` — override Python WS-client script path (for tests).
  - `:ws_url` — override the WebSocket endpoint URL (defaults to
    `EZAGENT_BRIDGE_WS_URL` env / `:ws_url` app config /
    `ws://127.0.0.1:10042/cc_socket/websocket`).
  """
  @spec write!(keyword()) :: {:ok, String.t()}
  def write!(opts) do
    agent_uri_str =
      Keyword.get(opts, :agent_uri) ||
        raise ArgumentError,
              "EzagentPluginCcChannel.McpConfigWriter.write!/1 requires :agent_uri"

    {:ok, token} = mint_token!(agent_uri_str)

    dir = Keyword.get(opts, :dir, Application.get_env(:ezagent_plugin_cc_channel, :mcp_config_dir, @default_dir))
    File.mkdir_p!(dir)

    script_path = Keyword.get(opts, :script_path, bridge_script_path())
    ws_url = Keyword.get(opts, :ws_url, resolve_ws_url())

    env = %{
      "EZAGENT_BRIDGE_WS_URL" => ws_url,
      "EZAGENT_AGENT_URI" => agent_uri_str,
      "EZAGENT_AGENT_TOKEN" => token
    }

    config = %{
      "mcpServers" => %{
        "esr-bridge" => %{
          "command" => "uv",
          "args" => ["run", "python3", script_path],
          "env" => env
        }
      }
    }

    encoded = Jason.encode!(config, pretty: true)

    path = Path.join(dir, @config_filename)
    File.write!(path, encoded)

    # Also write to project root so Claude's startup name lookup hits
    # the same config. Anchored on git toplevel so this works
    # regardless of cwd.
    case System.cmd("git", ["rev-parse", "--show-toplevel"], stderr_to_stdout: true) do
      {root, 0} ->
        root = String.trim(root)
        project_mcp = Path.join(root, ".mcp.json")
        File.write!(project_mcp, encoded)

      _ ->
        :ok
    end

    {:ok, path}
  end

  @doc "Absolute path of the v2 Python bridge script."
  @spec bridge_script_path() :: String.t()
  def bridge_script_path do
    Path.expand("../../../python/ezagent_mcp_bridge.py", __DIR__)
  end

  @doc """
  Resolved WebSocket URL for the bridge.

  Lookup order:
  1. `EZAGENT_BRIDGE_WS_URL` environment variable
  2. `Application.get_env(:ezagent_plugin_cc_channel, :ws_url)`
  3. `ws://127.0.0.1:10042/cc_socket/websocket` (matches Endpoint mount)
  """
  @spec resolve_ws_url() :: String.t()
  def resolve_ws_url do
    System.get_env("EZAGENT_BRIDGE_WS_URL") ||
      Application.get_env(:ezagent_plugin_cc_channel, :ws_url) ||
      "ws://127.0.0.1:10042/cc_socket/websocket"
  end

  defp mint_token!(agent_uri_str) when is_binary(agent_uri_str) do
    agent_uri = URI.parse(agent_uri_str)

    case TokenStore.mint(agent_uri) do
      {:ok, token} -> {:ok, token}
      {:error, reason} -> raise "TokenStore.mint failed for #{agent_uri_str}: #{inspect(reason)}"
    end
  end
end
