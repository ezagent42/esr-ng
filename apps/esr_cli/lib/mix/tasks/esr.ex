defmodule Mix.Tasks.Esr do
  @shortdoc "Auto-derived CLI for ESR Behavior actions + facade ops"
  @moduledoc """
  Phase 4-completion Spec 02: top-level `mix esr` task that auto-derives
  subcommands from `Esr.BehaviorRegistry` + `EsrCLI.FacadeRegistry`.

  ## Usage

      mix esr <kind> <action> [--<arg>=<val> ...] [--as <user_uri>] [--cast] [--json]

  Examples:

      mix esr workspace add_member --workspace default --member agent://x
      mix esr workspace create default --members user://admin,agent://x
      mix esr user list_caps --user admin

  Run `mix esr --help` for the full subcommand tree.
  """

  use Mix.Task

  alias EsrCLI.{Dispatch, Formatter, TreeBuilder}

  @impl Mix.Task
  def run(argv) do
    # Boot core + plugins so registries are populated
    boot_apps()

    spec = TreeBuilder.build()

    case Optimus.parse(spec, argv) do
      {:ok, _parsed_top_no_subcommand} ->
        IO.puts(Optimus.help(spec))
        exit_with(0)

      {:ok, subcommand_path, parsed} ->
        handle_subcommand(subcommand_path, parsed)

      {:error, _subcommand_path, errors} ->
        Enum.each(errors, fn e -> IO.puts(:stderr, "error: #{e}") end)
        exit_with(2)

      {:error, errors} when is_list(errors) ->
        Enum.each(errors, fn e -> IO.puts(:stderr, "error: #{e}") end)
        exit_with(2)

      :help ->
        IO.puts(Optimus.help(spec))
        exit_with(0)

      {:help, subcommand_path} ->
        sub_spec = Optimus.fetch_subcommand(spec, subcommand_path)
        IO.puts(Optimus.help(sub_spec))
        exit_with(0)

      :version ->
        IO.puts("esr 0.1.0")
        exit_with(0)
    end
  end

  defp handle_subcommand([kind_atom], _parsed) do
    # User typed `mix esr workspace` with no action — print subcommand help
    spec = TreeBuilder.build()
    sub = Optimus.fetch_subcommand(spec, [kind_atom])
    IO.puts(Optimus.help(sub))
    exit_with(0)
  end

  defp handle_subcommand([kind_atom, action_atom], parsed) do
    # Two paths: Behavior action OR facade op
    case find_behavior_for(kind_atom, action_atom) do
      {:ok, kind_module, behavior_module} ->
        result = Dispatch.run_action(kind_module, behavior_module, action_atom, parsed)
        json? = Map.get(parsed.flags, :json, false)
        exit_code = Formatter.render(result, json?)
        exit_with(exit_code)

      :error ->
        # Try facade op
        result = Dispatch.run_facade(kind_atom, action_atom, parsed)
        json? = Map.get(parsed.flags, :json, false)
        exit_code = Formatter.render(result, json?)
        exit_with(exit_code)
    end
  end

  defp handle_subcommand(other, _parsed) do
    IO.puts(:stderr, "error: unknown subcommand path: #{inspect(other)}")
    exit_with(2)
  end

  defp find_behavior_for(kind_atom, action_atom) do
    triples = Esr.BehaviorRegistry.list_all()

    Enum.find_value(triples, :error, fn {{kind_module, action}, behavior_module} ->
      if kind_module.type_name() == kind_atom and action == action_atom do
        {:ok, kind_module, behavior_module}
      else
        nil
      end
    end)
  end

  defp boot_apps do
    {:ok, _} = Application.ensure_all_started(:esr_core)
    plugins = Application.get_env(:esr_core, :cli_plugins, [:esr_plugin_echo, :esr_plugin_chat])

    Enum.each(plugins, fn app ->
      _ = Application.ensure_all_started(app)
    end)

    {:ok, _} = Application.ensure_all_started(:esr_cli)
    :ok
  end

  defp exit_with(code) when is_integer(code) do
    # In test env, raise instead of System.halt so ExUnit can catch.
    if Mix.env() == :test do
      throw({:cli_exit, code})
    else
      System.halt(code)
    end
  end
end
