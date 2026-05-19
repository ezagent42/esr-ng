defmodule EzagentCli.Exec do
  @moduledoc """
  Server-side CLI executor — Allen 2026-05-17 pivots.

  Called via distributed Erlang RPC from `Mix.Tasks.Esr` on the CLI
  side: `:rpc.call(ezagent_runtime@127.0.0.1, EzagentCli.Exec, :exec, [argv])`.
  Runs in the SAME BEAM as LV — same KindRegistry, same ETS tables,
  same Repo connections. No HTTP indirection, no separate VM.

      mix esr --(argv)→  :rpc.call → EzagentCli.Exec.exec/1
                                       ↓
                                [parse + Coerce + Invocation +
                                 dispatch — all in running BEAM]
                                       ↓
                       %{output, exit_code} (Elixir map, native term)
                                       ↓
      print + exit

  ## Return

  `%{output: String.t(), exit_code: 0..5}` — `output` is the
  rendered formatter result (text or JSON, depending on --json flag);
  `exit_code` follows EzagentCli.Formatter conventions.
  """

  alias EzagentCli.{Dispatch, Formatter, TreeBuilder}

  @spec exec([String.t()]) :: %{output: String.t(), exit_code: integer()}
  def exec(argv) when is_list(argv), do: exec(argv, [])

  @doc """
  PR #142: 2-arg form accepts CLI-level options. Currently:

    * `:token` — bearer token (verified via `Ezagent.Entity.authenticate/2`).
    * `:entity_uri` — the URI the token belongs to (required when
      `:token` is set; `entity_tokens` is keyed by URI).

  If both are present and valid, derived caller = that entity URI +
  its caps. If absent, falls back to admin caps (BC for single-user
  installs).
  """
  @spec exec([String.t()], keyword()) :: %{output: String.t(), exit_code: integer()}
  def exec(argv, opts) when is_list(argv) and is_list(opts) do
    case resolve_caller(opts[:token], opts[:entity_uri]) do
      {:ok, caller_uri, caller_caps} ->
        # Store on the per-call process dict so Dispatch.derive_caller
        # (in the same RPC-handling pid) picks it up without threading
        # opts through every command.
        Process.put(:ezagent_cli_caller_override, {caller_uri, caller_caps})

        try do
          do_exec(argv)
        after
          Process.delete(:ezagent_cli_caller_override)
        end

      {:error, :invalid_token} ->
        %{output: "error: invalid or revoked CLI token\n", exit_code: 4}

      {:error, :missing_entity_uri} ->
        %{
          output:
            "error: --token requires --uri (or EZAGENT_ENTITY_URI) since PR #142;\n" <>
              "       tokens live in entity_tokens, keyed by entity URI\n",
          exit_code: 4
        }
    end
  end

  defp do_exec(argv) do
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

  # nil / empty token → no override → Dispatch falls through to admin.
  defp resolve_caller(nil, _), do: {:ok, nil, nil}
  defp resolve_caller("", _), do: {:ok, nil, nil}

  defp resolve_caller(token, nil) when is_binary(token), do: {:error, :missing_entity_uri}
  defp resolve_caller(token, "") when is_binary(token), do: {:error, :missing_entity_uri}

  defp resolve_caller(token, entity_uri_str)
       when is_binary(token) and is_binary(entity_uri_str) do
    uri = URI.parse(entity_uri_str)

    case Ezagent.Entity.authenticate(uri, token) do
      {:ok, %{caps: caps}} -> {:ok, uri, caps}
      {:error, _} -> {:error, :invalid_token}
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
    {output, exit_code} = Formatter.render(result, json?)
    %{output: output, exit_code: exit_code}
  end

  defp handle_subcommand(other, _parsed, _spec) do
    %{output: "error: unknown subcommand path: #{inspect(other)}", exit_code: 2}
  end

  defp find_behavior_for(kind_atom, action_atom) do
    triples = Ezagent.BehaviorRegistry.list_all()

    Enum.find_value(triples, :error, fn {{kind_module, action}, behavior_module} ->
      # Defensive: skip test-leaked fake modules — same pattern as
      # EzagentCli.TreeBuilder.safe_type_name/1. Without this, an
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
