defmodule EsrCLI.Exec do
  @moduledoc """
  Server-side CLI executor — Allen 2026-05-17 pivot.

  This is the function that `EsrWeb.CliController.exec/2` calls when
  it receives a POST `/api/cli/exec` with `{argv: [...]}`. It runs
  in the SAME BEAM as LV, so dispatch hits the same KindRegistry,
  same ETS tables, same Repo connections. No separate VM.

  `mix esr` becomes a dumb HTTP shell:

      mix esr  --(argv)→  POST /api/cli/exec  →  EsrCLI.Exec.exec/1  →
                                                 ↓
                                          [parse + Coerce + Invocation
                                           + dispatch all in running BEAM]
                                                 ↓
                          {output, exit_code}  ←
      print + exit

  ## Return

  `%{output: String.t(), exit_code: 0..2}` — `output` is the
  rendered formatter result (text or JSON, depending on --json flag);
  `exit_code` mirrors what Mix.Tasks.Esr previously returned.
  """

  alias EsrCLI.{Dispatch, Formatter, TreeBuilder}

  @spec exec([String.t()]) :: %{output: String.t(), exit_code: integer()}
  def exec(argv) when is_list(argv) do
    spec = TreeBuilder.build()

    case Optimus.parse(spec, argv) do
      {:ok, _parsed_top_no_subcommand} ->
        %{output: Optimus.help(spec), exit_code: 0}

      {:ok, subcommand_path, parsed} ->
        handle_subcommand(subcommand_path, parsed, spec)

      {:error, _subcommand_path, errors} ->
        %{output: format_errors(errors), exit_code: 2}

      {:error, errors} when is_list(errors) ->
        %{output: format_errors(errors), exit_code: 2}

      :help ->
        %{output: Optimus.help(spec), exit_code: 0}

      {:help, subcommand_path} ->
        sub_spec = Optimus.fetch_subcommand(spec, subcommand_path)
        %{output: Optimus.help(sub_spec), exit_code: 0}

      :version ->
        %{output: "esr 0.1.0", exit_code: 0}
    end
  end

  defp handle_subcommand([kind_atom], _parsed, spec) do
    sub = Optimus.fetch_subcommand(spec, [kind_atom])
    %{output: Optimus.help(sub), exit_code: 0}
  end

  defp handle_subcommand([kind_atom, action_atom], parsed, _spec) do
    result =
      case find_behavior_for(kind_atom, action_atom) do
        {:ok, kind_module, behavior_module} ->
          Dispatch.run_action(kind_module, behavior_module, action_atom, parsed)

        :error ->
          Dispatch.run_facade(kind_atom, action_atom, parsed)
      end

    json? = Map.get(parsed.flags, :json, false)
    {output, exit_code} = Formatter.render_to_string(result, json?)
    %{output: output, exit_code: exit_code}
  end

  defp handle_subcommand(other, _parsed, _spec) do
    %{output: "error: unknown subcommand path: #{inspect(other)}", exit_code: 2}
  end

  defp find_behavior_for(kind_atom, action_atom) do
    triples = Esr.BehaviorRegistry.list_all()

    Enum.find_value(triples, :error, fn {{kind_module, action}, behavior_module} ->
      # Defensive: skip test-leaked fake modules — same pattern as
      # EsrCLI.TreeBuilder.safe_type_name/1. Without this, an
      # umbrella-test-leaked FakeK in BehaviorRegistry crashes the
      # CLI server-side path.
      case safe_type_name(kind_module) do
        nil ->
          nil

        ^kind_atom when action == action_atom ->
          {:ok, kind_module, behavior_module}

        _ ->
          nil
      end
    end)
  end

  defp safe_type_name(kind_mod) do
    if Code.ensure_loaded?(kind_mod) and function_exported?(kind_mod, :type_name, 0) do
      try do
        kind_mod.type_name()
      rescue
        _ -> nil
      catch
        _, _ -> nil
      end
    else
      nil
    end
  end

  defp format_errors(errors), do: Enum.map_join(errors, "\n", &("error: " <> &1))
end
