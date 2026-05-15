defmodule Esr.URI do
  @moduledoc """
  URI helpers — thin convenience over stdlib `URI`.

  ESR URIs follow `<scheme>://<instance>/behavior/<behavior_name>/<action>`
  for action invocation, with the instance form (`<scheme>://<instance>`)
  used for addressing and subscriptions. The scheme determines the Kind
  family (`agent://` / `session://` / `user://` / `resource://` etc.) but
  the specific Kind module is determined by the runtime registration —
  `Esr.KindRegistry` holds URI → pid, the pid's GenServer knows its own
  `kind_module`.

  Phase 1 scope: parse + extract the instance URI (drop the
  `/behavior/.../...` path) + extract `{behavior_name_atom, action_atom}`
  from the path. `SchemeRegistry` is intentionally minimal —
  the four schemes Phase 1 needs are hardcoded.
  """

  @known_schemes ~w(agent session user resource system)

  @doc """
  Parse a binary URI into a stdlib `%URI{}`. Raises on malformed input
  (let-it-crash — adapter is responsible for clean URIs).
  """
  @spec parse!(String.t()) :: URI.t()
  def parse!(s) when is_binary(s) do
    case URI.new(s) do
      {:ok, %URI{scheme: nil}} ->
        raise ArgumentError, "URI missing scheme: #{inspect(s)}"

      {:ok, %URI{scheme: scheme} = u} when scheme in @known_schemes ->
        u

      {:ok, %URI{scheme: scheme}} ->
        raise ArgumentError,
              "URI scheme #{inspect(scheme)} not in known set: #{inspect(@known_schemes)}"

      {:error, part} ->
        raise ArgumentError, "URI parse failed at #{inspect(part)}: #{inspect(s)}"
    end
  end

  @doc """
  Return the instance form of a URI — drop everything from the path on.

  `agent://echo/behavior/echo/say` → `%URI{scheme: "agent", host: "echo"}`.
  Used by dispatch to find the instance pid in KindRegistry.
  """
  @spec instance(URI.t()) :: URI.t()
  def instance(%URI{} = uri) do
    %URI{uri | path: nil, query: nil, fragment: nil}
  end

  @doc """
  Split the URI path into `{behavior_name_atom, action_atom}`.

  Expects path of form `/behavior/<name>/<action>`. Returns `{:error,
  :malformed_path}` if the path doesn't match.
  """
  @spec behavior_action(URI.t()) ::
          {:ok, {atom(), atom()}} | {:error, :malformed_path}
  def behavior_action(%URI{path: path}) when is_binary(path) do
    case String.split(path, "/", trim: true) do
      ["behavior", behavior_name, action] ->
        {:ok, {String.to_atom(behavior_name), String.to_atom(action)}}

      _ ->
        {:error, :malformed_path}
    end
  end

  def behavior_action(%URI{path: nil}), do: {:error, :malformed_path}

  @doc "Known scheme allowlist — used by `parse!/1`."
  def known_schemes, do: @known_schemes
end
