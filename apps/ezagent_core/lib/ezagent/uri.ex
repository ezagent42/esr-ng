defmodule Ezagent.URI do
  @moduledoc """
  URI helpers — thin convenience over stdlib `URI`.

  ESR URIs follow `<scheme>://<instance>/behavior/<behavior_name>/<action>`
  for action invocation, with the instance form (`<scheme>://<instance>`)
  used for addressing and subscriptions. The scheme determines the Kind
  family (`agent://` / `session://` / `user://` / `resource://` etc.) but
  the specific Kind module is determined by the runtime registration —
  `Ezagent.KindRegistry` holds URI → pid, the pid's GenServer knows its own
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
  Return the instance form of a URI — keep everything BEFORE the
  `/behavior/<name>/<action>` marker; drop the marker + everything
  after it.

  Examples:
  - `agent://echo/behavior/echo/say` → `%URI{scheme: "agent", host: "echo", path: nil}`
  - `agent://cc/demo-builder/behavior/chat/receive` (PR #131 path-style)
    → `%URI{scheme: "agent", host: "cc", path: "/demo-builder"}`
  - `agent://cc/demo-builder` (instance URI itself) → unchanged
  - `session://main/behavior/chat/send` → `%URI{scheme: "session", host: "main", path: nil}`

  Used by dispatch to find the instance pid in KindRegistry.
  """
  @spec instance(URI.t()) :: URI.t()
  def instance(%URI{path: nil} = uri), do: %URI{uri | query: nil, fragment: nil}

  def instance(%URI{path: path} = uri) when is_binary(path) do
    case String.split(path, "/behavior/", parts: 2) do
      [pre, _suffix] ->
        new_path = if pre == "", do: nil, else: pre
        %URI{uri | path: new_path, query: nil, fragment: nil}

      [_only] ->
        # No /behavior/ marker — this URI is already an instance form
        # with a path component (PR #131 path-style: `agent://cc/demo-builder`).
        # Strip only query + fragment.
        %URI{uri | query: nil, fragment: nil}
    end
  end

  @doc """
  Split the URI path on `"/behavior/"` and return the
  `{behavior_name_atom, action_atom}` from the suffix.

  Works for both pre-PR-#131 `<scheme>://<host>/behavior/<name>/<action>`
  and PR-#131 path-style `<scheme>://<type>/<name>/behavior/<bname>/<action>`.

  Returns `{:error, :malformed_path}` if the path lacks `/behavior/`
  or the suffix doesn't have exactly two segments.
  """
  @spec behavior_action(URI.t()) ::
          {:ok, {atom(), atom()}} | {:error, :malformed_path}
  def behavior_action(%URI{path: path}) when is_binary(path) do
    case String.split(path, "/behavior/", parts: 2) do
      [_pre, suffix] ->
        case String.split(suffix, "/", trim: true) do
          [behavior_name, action] ->
            {:ok, {String.to_atom(behavior_name), String.to_atom(action)}}

          _ ->
            {:error, :malformed_path}
        end

      [_only] ->
        {:error, :malformed_path}
    end
  end

  def behavior_action(%URI{path: nil}), do: {:error, :malformed_path}

  @doc "Known scheme allowlist — used by `parse!/1`."
  def known_schemes, do: @known_schemes
end
