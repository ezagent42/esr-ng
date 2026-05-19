defmodule Ezagent.URI do
  @moduledoc """
  URI helpers — thin convenience over stdlib `URI`.

  ## Shape

  Every Ezagent URI has two parts:

      <instance>[ /<sub-resource> ]

  The instance identifies a Kind in `KindRegistry`. The sub-resource
  (optional) addresses something about that instance — currently only
  `/behavior/<kind>/<action>` is defined, but the parser is open to
  future sub-resource types (`/auth/...`, `/snapshot/...`, etc.)
  without modification.

  ### Instance shape per scheme

      agent://<type>/<name>      # PR #131: type segment required
      session://<name>
      user://<name>
      resource://<name>
      system://<name>

  ### Sub-resource examples

      agent://cc/demo-builder/behavior/chat/receive
      session://main/behavior/chat/send
      user://admin/behavior/identity/check

  ## Parser layering (PR-A)

  - `instance/1` is **positional**: it knows where the instance ends
    based on scheme structure alone, NOT by searching for a keyword
    like "behavior". For `agent://`, that's `host + 1st path segment`;
    for all other schemes, it's `host` only.
  - `behavior_action/1` is **named**: it looks for the `behavior/`
    keyword in the sub-resource portion. A future `auth_action/1`
    would do the same for `auth/`. Each named parser returns `:error`
    for sub-resources it doesn't recognize.

  This split means adding a new sub-resource type (e.g. `auth/login`)
  only requires writing a new parser; `instance/1` doesn't change.
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
  Return the instance form of a URI — strip the sub-resource portion
  (and any query/fragment).

  **Positional split, scheme-aware** — does NOT search for keywords
  like `behavior`. The split point depends only on scheme structure:

  - `agent://` (PR #131): instance = `agent://<type>/<name>`,
    so the first path segment is part of the instance; segments
    2+ are the sub-resource.
  - All other schemes: instance = `<scheme>://<host>`, so the
    entire path is the sub-resource.

  Examples:
  - `agent://echo/default` → unchanged (no sub-resource)
  - `agent://cc/demo-builder/behavior/chat/receive`
    → `%URI{scheme: "agent", host: "cc", path: "/demo-builder"}`
  - `agent://cc/demo-builder/auth/whatever` (hypothetical)
    → `%URI{scheme: "agent", host: "cc", path: "/demo-builder"}`
  - `session://main/behavior/chat/send`
    → `%URI{scheme: "session", host: "main", path: nil}`

  Used by dispatch to find the instance pid in KindRegistry.
  """
  @spec instance(URI.t()) :: URI.t()
  def instance(%URI{path: nil} = uri), do: %URI{uri | query: nil, fragment: nil}

  def instance(%URI{scheme: "agent", path: "/" <> rest} = uri) do
    # agent://<type>/<name>[/<sub-resource...>]
    # The instance ends after the first path segment (the name).
    case String.split(rest, "/", parts: 2) do
      [_name_only] ->
        # path = "/<name>" — already pure instance
        %URI{uri | query: nil, fragment: nil}

      [name, _subresource] ->
        %URI{uri | path: "/" <> name, query: nil, fragment: nil}
    end
  end

  def instance(%URI{path: _path} = uri) do
    # Non-agent schemes: instance = <scheme>://<host>; path is sub-resource.
    %URI{uri | path: nil, query: nil, fragment: nil}
  end

  @doc """
  Parse the sub-resource portion of a URI looking for the `behavior/`
  keyword. Returns `{:ok, {behavior_atom, action_atom}}` or
  `{:error, :malformed_path}` (which also covers "this URI's
  sub-resource isn't a behavior call — e.g. it's `/auth/...`").

  **Named parser** — sibling to a hypothetical `auth_action/1`. The
  parser is scheme-aware in the same way `instance/1` is: it knows
  where the sub-resource starts (positional) and then looks for the
  `behavior/` prefix within that sub-resource.

  Examples:
  - `agent://echo/default/behavior/echo/say` → `{:ok, {:echo, :say}}`
  - `agent://cc/demo-builder/behavior/chat/receive` → `{:ok, {:chat, :receive}}`
  - `session://main/behavior/chat/send` → `{:ok, {:chat, :send}}`
  - `agent://cc/demo-builder/auth/login` → `{:error, :malformed_path}`
  - `agent://cc/demo-builder` → `{:error, :malformed_path}`
  """
  @spec behavior_action(URI.t()) ::
          {:ok, {atom(), atom()}} | {:error, :malformed_path}
  def behavior_action(%URI{} = uri) do
    case subresource(uri) do
      "behavior/" <> rest ->
        case String.split(rest, "/", trim: true) do
          [behavior_name, action] ->
            {:ok, {String.to_atom(behavior_name), String.to_atom(action)}}

          _ ->
            {:error, :malformed_path}
        end

      _ ->
        {:error, :malformed_path}
    end
  end

  @doc """
  Return the sub-resource portion of a URI as a string (no leading
  slash), or `""` if there is none.

  **Positional, scheme-aware** — the mirror image of `instance/1`.
  Made public so future named parsers (e.g. `auth_action/1`) can
  reuse the same split rule without re-deriving it.

  Examples:
  - `agent://echo/default` → `""`
  - `agent://cc/demo-builder/behavior/chat/receive` → `"behavior/chat/receive"`
  - `agent://cc/demo-builder/auth/login` → `"auth/login"`
  - `session://main/behavior/chat/send` → `"behavior/chat/send"`
  - `user://admin` → `""`
  """
  @spec subresource(URI.t()) :: String.t()
  def subresource(%URI{path: nil}), do: ""

  def subresource(%URI{scheme: "agent", path: "/" <> rest}) do
    case String.split(rest, "/", parts: 2) do
      [_name_only] -> ""
      [_name, sub] -> sub
    end
  end

  def subresource(%URI{path: "/" <> sub}), do: sub
  def subresource(%URI{path: ""}), do: ""

  @doc "Known scheme allowlist — used by `parse!/1`."
  def known_schemes, do: @known_schemes
end
