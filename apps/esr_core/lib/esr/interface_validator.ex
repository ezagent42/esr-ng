defmodule Esr.InterfaceValidator do
  @moduledoc """
  Recursive type-spec validator for `@interface` args / returns maps.

  Type-spec grammar (per ARCHITECTURE.md §6.2):
  - `:string` / `:integer` / `:boolean` / `:atom` / `:map` — primitives
  - `{:list, ty}` — homogeneous list
  - `{:tuple, [ty1, ty2, ...]}` — fixed-arity tuple
  - `{:option, ty}` — `nil` or `ty`
  - `%{field => ty, ...}` — record shape (all fields required unless
    declared `{:option, _}`)

  Phase 1 validation runs inside `Esr.Kind.Runtime.handle_dispatch/3`
  after BehaviorRegistry lookup so we have the Behavior's `@interface`
  in hand. Failure returns `{:error, {:invalid_args, [{field, reason}]}}`
  with a violations list — adapters surface this back to the caller.
  """

  @type type_spec ::
          :string
          | :integer
          | :boolean
          | :atom
          | :map
          | {:list, type_spec()}
          | {:tuple, [type_spec()]}
          | {:option, type_spec()}
          | %{optional(atom()) => type_spec()}

  @type violation :: {path :: [atom()], reason :: term()}

  @doc """
  Validate `args` against `schema` (a map of `field => type_spec`).

  Returns `:ok` if every field in `schema` is present and well-typed
  in `args`; otherwise `{:error, {:invalid_args, violations}}` listing
  every problem found (so callers see all failures, not just the first).
  """
  @spec validate(map(), map()) :: :ok | {:error, {:invalid_args, [violation()]}}
  def validate(args, schema) when is_map(args) and is_map(schema) do
    violations =
      schema
      |> Enum.flat_map(fn {field, ty} ->
        case check(Map.get(args, field, :__missing__), ty, [field]) do
          :ok -> []
          {:error, vs} -> vs
        end
      end)

    case violations do
      [] -> :ok
      _ -> {:error, {:invalid_args, violations}}
    end
  end

  # --- Recursive type check ----------------------------------------------

  defp check(:__missing__, {:option, _ty}, _path), do: :ok
  defp check(:__missing__, _ty, path), do: {:error, [{path, :missing}]}

  defp check(value, :string, _path) when is_binary(value), do: :ok
  defp check(value, :integer, _path) when is_integer(value), do: :ok
  defp check(value, :boolean, _path) when is_boolean(value), do: :ok
  defp check(value, :atom, _path) when is_atom(value), do: :ok
  defp check(value, :map, _path) when is_map(value), do: :ok

  defp check(nil, {:option, _ty}, _path), do: :ok
  defp check(value, {:option, ty}, path), do: check(value, ty, path)

  defp check(value, {:list, ty}, path) when is_list(value) do
    violations =
      value
      |> Enum.with_index()
      |> Enum.flat_map(fn {item, idx} ->
        case check(item, ty, path ++ [idx]) do
          :ok -> []
          {:error, vs} -> vs
        end
      end)

    if violations == [], do: :ok, else: {:error, violations}
  end

  defp check(value, {:tuple, tys}, path) when is_tuple(value) do
    if tuple_size(value) != length(tys) do
      {:error, [{path, {:expected_tuple_size, length(tys), :got, tuple_size(value)}}]}
    else
      violations =
        tys
        |> Enum.with_index()
        |> Enum.flat_map(fn {ty, idx} ->
          case check(elem(value, idx), ty, path ++ [idx]) do
            :ok -> []
            {:error, vs} -> vs
          end
        end)

      if violations == [], do: :ok, else: {:error, violations}
    end
  end

  defp check(value, ty, path) when is_map(ty) and is_map(value) do
    violations =
      ty
      |> Enum.flat_map(fn {field, inner_ty} ->
        case check(Map.get(value, field, :__missing__), inner_ty, path ++ [field]) do
          :ok -> []
          {:error, vs} -> vs
        end
      end)

    if violations == [], do: :ok, else: {:error, violations}
  end

  defp check(value, ty, path),
    do: {:error, [{path, {:type_mismatch, expected: ty, got: value}}]}
end
