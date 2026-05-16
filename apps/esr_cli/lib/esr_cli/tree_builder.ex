defmodule EsrCLI.TreeBuilder do
  @moduledoc """
  Walks `Esr.BehaviorRegistry.list_all/0` + `EsrCLI.FacadeRegistry`
  and produces the Optimus subcommand tree.

  Top-level: `mix esr` → subcommands per Kind. Each Kind subcommand
  has further subcommands per Behavior action (auto-derived) + per
  facade op (registered).

  Per Spec 02 §3: rebuilt every invocation; the walk is O(#actions) ~20
  today, trivial. No compile-time caching that would couple CLI shape
  to compile order.
  """

  alias EsrCLI.{Coercion, FacadeRegistry}

  @doc """
  Build the Optimus root spec. `behavior_triples` is
  `[{{kind_module, action}, behavior_module}, ...]` from
  `BehaviorRegistry.list_all/0`.
  """
  @spec build(list()) :: Optimus.t()
  def build(behavior_triples \\ Esr.BehaviorRegistry.list_all()) do
    # Filter stale entries — when test suites register fake Kind
    # modules per-test, those modules may no longer be loadable when
    # build() runs later. Skip rather than crash.
    by_kind =
      behavior_triples
      |> Enum.filter(fn {{kind_mod, _action}, _bhv} ->
        Code.ensure_loaded?(kind_mod) and function_exported?(kind_mod, :type_name, 0)
      end)
      |> Enum.group_by(fn {{kind_mod, _action}, _bhv} -> kind_mod end)

    kind_subcommands =
      by_kind
      |> Enum.map(fn {kind_module, actions} ->
        type_name = kind_module.type_name()
        {type_name, kind_subcommand(kind_module, type_name, actions)}
      end)

    # Facade-only kinds (registered ops with no matching Behavior actions)
    facade_only_kinds =
      FacadeRegistry.list_kinds()
      |> Enum.reject(fn kt -> Enum.any?(by_kind, fn {km, _} -> km.type_name() == kt end) end)
      |> Enum.reject(&is_nil/1)

    facade_only_subcommands =
      facade_only_kinds
      |> Enum.map(fn type_name ->
        {type_name, facade_only_subcommand(type_name)}
      end)

    Optimus.new!(
      name: "esr",
      description: "ESR Invocation CLI — auto-derived from BehaviorRegistry + FacadeRegistry",
      version: "0.1.0",
      allow_unknown_args: false,
      parse_double_dash: true,
      subcommands: kind_subcommands ++ facade_only_subcommands
    )
  end

  defp kind_subcommand(kind_module, type_name, actions) do
    action_subs =
      actions
      |> Enum.map(fn {{_kind, action}, behavior_module} ->
        {action, action_subcommand(kind_module, type_name, behavior_module, action)}
      end)

    facade_subs =
      FacadeRegistry.list(type_name)
      |> Enum.map(fn {op_name, _fun, spec} ->
        {op_name, facade_subcommand(type_name, op_name, spec)}
      end)

    [
      name: to_string(type_name),
      about: "Actions on #{type_name}://<instance>",
      subcommands: action_subs ++ facade_subs
    ]
  end

  defp action_subcommand(_kind_module, type_name, behavior_module, action) do
    interface = behavior_module.interface()[action] || %{}
    args_spec = Map.get(interface, :args, %{})
    modes = Map.get(interface, :modes, [:call])

    # Instance arg: --<type_name> required
    instance_opt =
      {type_name,
       [
         value_name: String.upcase(to_string(type_name)),
         long: to_string(type_name) |> String.replace("_", "-"),
         parser: :string,
         required: true
       ]}

    # Schema args as options
    arg_options =
      args_spec
      |> Enum.map(fn {arg_name, arg_type} ->
        Coercion.to_option(arg_name, arg_type, required: true)
      end)

    # --cast flag if both :call and :cast are supported
    cast_flag =
      if :cast in modes do
        [cast: [long: "cast"]]
      else
        []
      end

    # --as flag for caller override (Spec 02 §2.F)
    as_opt = {:as, [long: "as", value_name: "USER_URI", parser: :string]}

    # --json flag for machine-readable output
    json_flag = [json: [long: "json"]]

    # --deadline-ms
    deadline_opt = {:deadline_ms, [long: "deadline-ms", value_name: "MS", parser: :integer]}

    [
      name: to_string(action),
      about: action_about(behavior_module, action),
      options: [instance_opt | arg_options] ++ [as_opt, deadline_opt],
      flags: cast_flag ++ json_flag
    ]
  end

  defp action_about(behavior_module, action) do
    # Per Spec 02 Q-H: per-action @doc extraction, fallback generic.
    case Code.fetch_docs(behavior_module) do
      {:docs_v1, _, _, _, _, _, fn_docs} ->
        Enum.find_value(fn_docs, fn
          {{:function, ^action, _arity}, _, _, %{"en" => text}, _} -> text
          _ -> nil
        end) || "#{action} action on #{behavior_module}"

      _ ->
        "#{action} action on #{behavior_module}"
    end
  end

  defp facade_subcommand(_kind_type, op_name, spec) do
    args_keyword =
      Map.get(spec, :args, [])
      |> Enum.map(fn {name, type} ->
        {name, [value_name: String.upcase(to_string(name)), parser: parser_for(type), required: true]}
      end)

    opts_keyword =
      Map.get(spec, :opts, [])
      |> Enum.map(fn {name, type} ->
        Coercion.to_option(name, type, required: false)
      end)

    [
      name: to_string(op_name),
      about: spec[:about] || "facade op",
      args: args_keyword,
      options: opts_keyword,
      flags: [json: [long: "json"]]
    ]
  end

  defp facade_only_subcommand(type_name) do
    facade_subs =
      FacadeRegistry.list(type_name)
      |> Enum.map(fn {op_name, _fun, spec} ->
        {op_name, facade_subcommand(type_name, op_name, spec)}
      end)

    [
      name: to_string(type_name),
      about: "Facade ops for #{type_name}",
      subcommands: facade_subs
    ]
  end

  defp parser_for(:string), do: :string
  defp parser_for(:integer), do: :integer

  defp parser_for(:uri),
    do: fn s ->
      case URI.new(s) do
        {:ok, %URI{scheme: scheme} = u} when is_binary(scheme) -> {:ok, u}
        _ -> {:error, "malformed URI: #{inspect(s)}"}
      end
    end

  defp parser_for(_), do: :string
end
