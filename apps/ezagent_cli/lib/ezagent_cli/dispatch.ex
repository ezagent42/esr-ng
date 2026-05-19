defmodule EzagentCli.Dispatch do
  @moduledoc """
  Build `%Ezagent.Invocation{}` from parsed Optimus result and dispatch.

  Constructs target URI from the `--<kind_type>` instance arg, threads
  caps from caller's Identity slice (or admin default), waits on the
  caller mailbox for `:call` mode.
  """

  alias Ezagent.{Invocation, KindRegistry}

  @default_deadline_ms 5000

  @doc """
  Dispatch an auto-derived action.

  `kind_module` + `behavior_module` + `action` identify which action.
  `parsed` is the Optimus `%{options:, flags:, args:}` for the subcommand.
  """
  @spec run_action(module(), module(), atom(), map()) :: {:ok, term()} | {:error, term()}
  def run_action(kind_module, behavior_module, action, parsed) do
    type_name = kind_module.type_name()
    options = Map.get(parsed, :options, %{})
    flags = Map.get(parsed, :flags, %{})

    # Build URI
    case Map.get(options, type_name) do
      nil ->
        {:error, {:missing_instance_arg, type_name}}

      instance ->
        target_uri = build_target_uri(type_name, instance, behavior_module, action)

        # Extract action args (everything except --<type_name>, --as, --deadline-ms)
        reserved = MapSet.new([type_name, :as, :deadline_ms])
        action_args = Map.drop(options, MapSet.to_list(reserved))

        # Determine mode
        mode =
          if Map.get(flags, :cast, false) do
            :cast
          else
            interface = behavior_module.interface()[action] || %{}
            modes = Map.get(interface, :modes, [:call])

            cond do
              :call in modes -> :call
              :cast in modes -> :cast
              true -> :call
            end
          end

        # Caller + caps
        {caller_uri, caps} = derive_caller(options)

        deadline_ms = Map.get(options, :deadline_ms) || @default_deadline_ms

        inv = %Invocation{
          target: target_uri,
          mode: mode,
          args: action_args,
          ctx: %{
            caller: caller_uri,
            caps: caps,
            reply: {:caller_inbox, self()},
            deadline_ms: deadline_ms
          }
        }

        do_dispatch(inv, mode, deadline_ms)
    end
  end

  @doc """
  Run a registered facade op by looking it up + calling with parsed args.
  """
  @spec run_facade(atom() | nil, atom(), map()) :: {:ok, term()} | {:error, term()}
  def run_facade(kind_type, op_name, parsed) do
    case EzagentCli.FacadeRegistry.lookup(kind_type, op_name) do
      {:ok, fun, _spec} -> fun.(parsed)
      :error -> {:error, {:no_such_facade, kind_type, op_name}}
    end
  end

  defp build_target_uri(type_name, instance, behavior_module, action) do
    scheme = scheme_for(type_name)
    behavior_seg = behavior_module.state_slice() |> to_string()

    # SPEC v2 §5.2 (PR #148): action lives in ?action=<behavior>.<action> query.
    URI.parse(
      "#{scheme}://#{instance}?action=#{behavior_seg}.#{to_string(action)}"
    )
  end

  # Phase 4 completion: scheme defaults to type_name. Echo overrides
  # by using `entity://agent/` for instances — but for CLI we use type_name
  # consistently. Phase 5+ can add scheme/0 callback on Kind if needed.
  defp scheme_for(type_name), do: to_string(type_name)

  defp derive_caller(options) do
    # Phase 6 PR 7: per-process override set by `EzagentCli.Exec.exec/2`
    # when a valid CLI bearer token is presented. This takes precedence
    # over the legacy `--as` flag — token auth IS the caller identity.
    case Process.get(:ezagent_cli_caller_override) do
      {%URI{} = uri, %MapSet{} = caps} ->
        {uri, caps}

      _ ->
        case Map.get(options, :as) do
          nil ->
            {Ezagent.Entity.User.admin_uri(), Ezagent.Entity.User.admin_caps()}

          as_str ->
            case System.get_env("EZAGENT_CLI_ALLOW_AS") do
              "1" -> derive_other_user(as_str)
              _ -> {:error, :as_not_allowed}
            end
        end
    end
  end

  defp derive_other_user(as_str) do
    case URI.new(as_str) do
      {:ok, uri} ->
        caps = lookup_identity_caps(uri)
        {uri, caps}

      _ ->
        {:error, {:bad_as_uri, as_str}}
    end
  end

  defp lookup_identity_caps(uri) do
    case KindRegistry.lookup(uri) do
      {:ok, pid} ->
        try do
          %{state: %{identity: %{caps: caps}}} = :sys.get_state(pid, 1_000)
          caps
        catch
          _, _ -> MapSet.new()
        end

      :error ->
        MapSet.new()
    end
  end

  # Restored to local dispatch — the pivot (Allen 2026-05-17) moves the
  # CLI VM problem upstream: Mix.Tasks.Esr no longer runs Dispatch
  # locally; it POSTs argv to the server's /api/cli/exec which runs
  # EzagentCli.Exec.exec → eventually calls THIS function inside the
  # running phx BEAM. So this code stays local — it's just that it
  # now runs in the right BEAM.
  defp do_dispatch(inv, :call, deadline_ms) do
    case Invocation.dispatch(inv) do
      {:ok, result} ->
        {:ok, result}

      :ok ->
        receive do
          {:ezagent_reply, reply} -> {:ok, reply}
        after
          deadline_ms -> {:ok, :ok}
        end

      {:error, _} = err ->
        err
    end
  end

  defp do_dispatch(inv, :cast, _deadline_ms) do
    case Invocation.dispatch(inv) do
      :ok -> {:ok, :ok}
      {:ok, _} -> {:ok, :ok}
      {:error, _} = err -> err
    end
  end
end
