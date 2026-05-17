defmodule Esr.TemplateRegistry do
  @moduledoc """
  Registry mapping Template Class names to Class modules.

  Phase 4 completion: the runtime DI pattern for `Esr.Kind.Template`
  Classes, parallel to `Esr.SpawnRegistry` for Kind spawn fns.

  Plugin authors register their Template Classes in `Application.start/2`:

      Esr.TemplateRegistry.register(EsrDomainChat.Template.GenericSession)

  When `Esr.Workspace.Loader` walks a Workspace's `session_templates`
  on boot, it looks up the Class via `template_name` from the template
  data and calls `Class.instantiate/3` — esr_core never references
  any concrete Class module.

  ## Strict duplicate registration (per Q3)

  Two plugins claiming the same `template_name` is a real bug, not a
  feature. `register/1` returns `{:error, {:duplicate, existing_module,
  attempted_module}}` on collision; plugin author must pick a different
  name. (Contrast with `SpawnRegistry` which is late-binding-wins —
  scheme collisions there are rarer.)

  ## ETS layout

  `:esr_template_registry` set table owned by `EsrCore.EtsOwner`. Keys
  are template_name strings, values are Class module atoms (NOT 0-arity
  fns — we call `module.template_name/0` to populate, so we already
  have the module reference).
  """

  @table :esr_template_registry

  def table, do: @table

  @doc """
  Register a Template Class. Reads `template_name/0` from the module
  to derive the registry key (single source of truth).

  Returns `:ok` on success, `{:error, {:duplicate, existing, attempted}}`
  if another module is already registered under the same name.
  """
  @spec register(module()) :: :ok | {:error, term()}
  def register(class_module) when is_atom(class_module) do
    name = class_module.template_name()

    case :ets.lookup(@table, name) do
      [{^name, ^class_module}] ->
        :ok

      [{^name, existing}] ->
        {:error, {:duplicate, existing, class_module}}

      [] ->
        :ets.insert(@table, {name, class_module})
        :ok
    end
  end

  @doc "Look up a Template Class module by name."
  @spec lookup(String.t()) :: {:ok, module()} | :error
  def lookup(name) when is_binary(name) do
    case :ets.lookup(@table, name) do
      [{^name, class_module}] -> {:ok, class_module}
      [] -> :error
    end
  end

  @doc "List registered Template Class names (for debugging / mix tasks)."
  @spec registered_template_names() :: [String.t()]
  def registered_template_names do
    :ets.tab2list(@table)
    |> Enum.map(fn {name, _module} -> name end)
    |> Enum.sort()
  end
end
