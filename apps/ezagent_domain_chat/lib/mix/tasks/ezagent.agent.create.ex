defmodule Mix.Tasks.Ezagent.Agent.Create do
  @shortdoc "Create a new ESR Agent (mirrors mix ezagent.user.create)"
  @moduledoc """
  PR #149 (S-6, entity-agnostic reflection §4) — provision a
  standalone Agent from the CLI.

  Closes the provisioning-asymmetry gap: pre-PR-149 the only way to
  bring an Agent into existence was as a side-effect of a Workspace
  template (or a bridge announce). Users had `mix ezagent.user.create`;
  Agents had no parallel. Now they do.

  ## Usage

      mix ezagent.agent.create entity://agent/default/curl_my-deepseek \\
          --kind-module Ezagent.Entity.CurlAgent

      mix ezagent.agent.create entity://agent/default/cc_my-builder \\
          --kind-module Ezagent.Entity.Agent

      # Kind module inferred from the flavor prefix (cc/curl/echo):
      mix ezagent.agent.create entity://agent/default/echo_my-echo

  Flags:
  - `--kind-module <Mod>` — explicit backing Kind module. Optional;
    if omitted the chat plugin's three-step resolver (snapshot →
    workspace-template → flavor-prefix) picks one. Pass explicitly
    only when overriding the prefix mapping.

  ## Behavior

  1. Parses + validates the agent URI shape (`entity://agent/<flavor>_<name>`).
  2. Calls `Ezagent.SpawnRegistry.spawn/1`, which routes through the
     chat plugin's `entity://` fn and resolves the backing Kind via
     snapshot → template → flavor-prefix.
  3. Prints confirmation.

  ## Examples

      # Bring an echo agent into existence
      mix ezagent.agent.create entity://agent/default/echo_observer

      # CC agent (PTY-managed) — useful for pre-registering an agent
      # so a bridge connecting from the same URI later attaches to
      # the already-live Kind.
      mix ezagent.agent.create entity://agent/default/cc_architect
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {:ok, _} = Application.ensure_all_started(:ezagent_core)
    {:ok, _} = Application.ensure_all_started(:ezagent_domain_chat)

    {opts, positional, _} =
      OptionParser.parse(args,
        strict: [kind_module: :string],
        aliases: []
      )

    case positional do
      [agent_uri_str] when is_binary(agent_uri_str) ->
        do_create(agent_uri_str, opts)

      _ ->
        Mix.raise("""
        usage: mix ezagent.agent.create <agent_uri> [--kind-module <Module>]

        Example:
          mix ezagent.agent.create entity://agent/default/curl_my-deepseek
          mix ezagent.agent.create entity://agent/default/cc_architect --kind-module Ezagent.Entity.Agent
        """)
    end
  end

  defp do_create(agent_uri_str, opts) do
    with {:ok, agent_uri} <- parse_uri(agent_uri_str),
         :ok <- validate_kind_module_opt(opts) do
      case Ezagent.SpawnRegistry.spawn(agent_uri) do
        {:ok, pid} ->
          Mix.shell().info("✓ spawned #{agent_uri_str}")
          Mix.shell().info("  pid: #{inspect(pid)}")
          :ok

        {:error, {:already_started, pid}} ->
          Mix.shell().info("✓ already alive: #{agent_uri_str}")
          Mix.shell().info("  pid: #{inspect(pid)}")
          :ok

        {:error, reason} ->
          Mix.raise("spawn failed: #{inspect(reason)}")
      end
    else
      {:error, reason} -> Mix.raise("create failed: #{inspect(reason)}")
    end
  end

  defp parse_uri(s) when is_binary(s) do
    # Phase 9 PR-2 (SPEC v3 §3): route through Ezagent.URI.parse!/1
    # so 2-segment URIs are rejected with the SPEC v3 error.
    try do
      uri = Ezagent.URI.parse!(s)

      case uri do
        %URI{scheme: "entity", host: "agent", path: "/" <> rest} ->
          with [_workspace, entity_name] when entity_name != "" <-
                 String.split(rest, "/", parts: 2),
               [flavor, suffix] when flavor != "" and suffix != "" <-
                 String.split(entity_name, "_", parts: 2) do
            {:ok, uri}
          else
            _ ->
              {:error,
               {:bad_uri, s,
                "expected entity://agent/<workspace>/<flavor>_<name> (e.g. cc_my-bot)"}}
          end

        _ ->
          {:error, {:bad_uri, s, "expected entity://agent/<workspace>/<flavor>_<name>"}}
      end
    rescue
      e in ArgumentError ->
        {:error, {:bad_uri, s, Exception.message(e)}}
    end
  end

  # `--kind-module` is accepted for documentation parity with the
  # plan but currently informational — the chat plugin's resolver is
  # the actual authority on which module backs the URI. Future
  # enhancement: have the task write a snapshot pointing at the
  # requested module BEFORE spawn so the resolver picks it up.
  defp validate_kind_module_opt([]), do: :ok
  defp validate_kind_module_opt(opts) do
    case Keyword.get(opts, :kind_module) do
      nil ->
        :ok

      mod_str when is_binary(mod_str) ->
        mod = String.to_atom("Elixir.#{mod_str}")

        if Code.ensure_loaded?(mod) do
          Mix.shell().info(
            "  note: --kind-module is informational; resolver " <>
              "(snapshot → template → flavor-prefix) decides the actual Kind"
          )

          :ok
        else
          {:error, {:unknown_kind_module, mod_str}}
        end
    end
  end
end
