defmodule Esr.Bridge.V1Prototype.McpConfigWriter do
  @moduledoc """
  Writes the `.mcp.json` that Claude Code consumes via `--mcp-config`.

  Output path: `~/.openclaw/esr-ng/bridge.mcp.json` by default
  (configurable via `Application.get_env(:esr_plugin_cc_bridge_v1_prototype,
  :mcp_config_path)`). When Claude starts with `--mcp-config <path>` it
  reads this file, then spawns each declared MCP server as a stdio
  subprocess. The "esr-bridge" server is our v1 Python module
  (`esr_mcp_bridge_v1_prototype.py`).

  ## What `write!/0` does

  1. Computes absolute path of `esr_mcp_bridge_v1_prototype.py`
  2. Resolves esrd URL (env `ESR_BRIDGE_ESRD_URL` or config or
     `http://127.0.0.1:4000`)
  3. Writes JSON pointing claude at `uv run python3 <abs script>` with
     the env var injected
  4. Returns `{:ok, path}` so the attach script can `--mcp-config <path>`

  ## Phase 5 replacement

  In Phase 5 the OSProcess Behavior generates this config dynamically
  per-session inside ESR. v1_prototype writes it once to a shared path
  because we only spawn one CC instance for the demo.
  """

  @default_dir Path.expand("~/.openclaw/esr-ng")
  @config_filename "bridge.mcp.json"

  @doc """
  Write the bridge mcp.json. Returns `{:ok, abs_path}`.

  Also writes a copy to the project root `.mcp.json` (a "drop file"
  for Claude Code). Without the project-level file, Claude prints a
  startup warning `server:esr-bridge · no MCP server configured with
  that name` because `--dangerously-load-development-channels` looks
  up the server name in project/user MCP configs **before** reading
  `--mcp-config <abs>`. The project-level file makes the lookup
  succeed at the right moment, suppressing the warning. The session-
  level `--mcp-config <abs>` flag remains too so explicit pathing is
  preserved.
  """
  @spec write!() :: {:ok, String.t()}
  def write! do
    dir = Application.get_env(:esr_plugin_cc_bridge_v1_prototype, :mcp_config_dir, @default_dir)
    File.mkdir_p!(dir)

    config = %{
      "mcpServers" => %{
        "esr-bridge" => %{
          "command" => "uv",
          "args" => ["run", "python3", bridge_script_path()],
          "env" => %{
            "ESRD_URL" => esrd_url()
          }
        }
      }
    }

    encoded = Jason.encode!(config, pretty: true)

    path = Path.join(dir, @config_filename)
    File.write!(path, encoded)

    # Also write to project root so claude's startup lookup matches.
    # Use git toplevel as anchor so this works regardless of cwd.
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

  @doc "Absolute path of the Python bridge script."
  @spec bridge_script_path() :: String.t()
  def bridge_script_path do
    Path.expand(
      "../../../../python/esr_mcp_bridge_v1_prototype.py",
      __DIR__
    )
  end

  @doc "Configured esrd URL (env or config or default)."
  @spec esrd_url() :: String.t()
  def esrd_url do
    System.get_env("ESR_BRIDGE_ESRD_URL") ||
      Application.get_env(:esr_plugin_cc_bridge_v1_prototype, :esrd_url) ||
      "http://127.0.0.1:4000"
  end
end
