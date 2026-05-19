defmodule Ezagent.URI do
  @moduledoc """
  URI helpers — thin convenience over stdlib `URI`.

  ## Shape (SPEC v2 — PR #141 onwards)

  SPEC v2 §5.1 defines the **target** uniform 2-segment authority
  for every Ezagent URI:

      <scheme>://<type>/<name>[/<sub-resource>...]

  - `<scheme>` is one of the registered schemes (see `@known_schemes`).
  - `<type>` is the value on the scheme's type axis (e.g. `user` /
    `agent` for `entity://`, free-form tenant name for `workspace://`).
  - `<name>` is the instance identity within `<scheme>/<type>`.
  - Anything after `/<name>` is sub-resource (currently only
    `/behavior/<kind>/<action>` is defined; the parser is open).

  PR #141 implements the migration for the `entity://` scheme (user
  + agent merged). The other 2-seg-target schemes (`workspace://`,
  `session://`, `template://`, `resource://`, `system://`) migrate
  in later PRs (#143/#144/#146) — until then their existing 1-seg
  shape is preserved by `instance/1` (legacy clause).

  ### Examples

      entity://user/admin
      entity://agent/cc_demo-builder
      session://main             # legacy 1-seg, migrating in #147
      workspace://default        # legacy 1-seg, migrating in #147
      template://agent/cc-orchestrator
      system://routing/default   # 2-seg (PR #146)

  ## SPEC v2 deltas (PR #141)

  - `user://` + `agent://` schemes deleted — merged into `entity://`.
  - `instance/1` is now **uniform across all schemes**: it splits
    on `host + /<first-path-segment>`, treating every URI the same.
    The pre-PR-141 agent-specific clause is gone.
  - Agent flavor (cc / curl / echo) moves OUT of the URI type segment
    INTO the name segment as a free-form prefix:
    `entity://agent/cc_demo-builder`, `entity://agent/curl_my-deepseek`
    (SPEC §5.14).

  ## Parser layering

  - `instance/1` is **positional**: it knows where the instance ends
    based on uniform structure (always `host + /first-path-segment`),
    NOT by searching for a keyword like "behavior".
  - `behavior_action/1` is **named**: it looks for the `behavior/`
    keyword in the sub-resource portion. A future `auth_action/1`
    would do the same for `auth/`. Each named parser returns `:error`
    for sub-resources it doesn't recognize.

  ## Deferred-deletion schemes

  `message` remains in `@known_schemes` for now — PR #147 deletes it.

  - PR #144 deleted `feishu` (Feishu plugin re-shaped per SPEC §5.8)
  - PR #146 deleted `routing-admin` + `pty-input` (synthetic singletons
    dissolved per SPEC §5.7 — Behaviors moved to scope-owning Kinds)
  - PR #147 deletes `message`
  """

  @known_schemes ~w(entity workspace session template resource system message)

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

  **PR #141 + #146 SPEC v2 transitional rule**: 2-segment-authority
  schemes use the uniform split `host + /<first-path-segment>`:
  - `entity://` (PR #141)
  - `system://` (PR #146 — `system://routing/default`,
    `system://bootstrap/default`)

  Remaining schemes (`session://`, `workspace://`, `template://`,
  `resource://`, `message://`) keep the legacy "strip entire path"
  behavior until PR #147 migrates them along with the query-string
  action syntax.

  Examples:
  - `entity://user/admin` → unchanged (no sub-resource)
  - `entity://agent/cc_demo-builder/behavior/chat/receive`
    → `%URI{scheme: "entity", host: "agent", path: "/cc_demo-builder"}`
  - `system://routing/default/behavior/routing/add_rule`
    → `%URI{scheme: "system", host: "routing", path: "/default"}`
  - `session://main/behavior/chat/send`
    → `%URI{scheme: "session", host: "main", path: nil}` (legacy
       1-seg session URI; path stripped entirely)
  - `workspace://default/main` → unchanged

  Used by dispatch to find the instance pid in KindRegistry.
  """
  @spec instance(URI.t()) :: URI.t()
  def instance(%URI{path: nil} = uri), do: %URI{uri | query: nil, fragment: nil}

  def instance(%URI{scheme: "entity", path: "/" <> rest} = uri) do
    # PR #141 SPEC v2 §5.1 — uniform 2-segment authority for entity:
    # entity://<type>/<name>[/<sub-resource>...]
    case String.split(rest, "/", parts: 2) do
      [_name_only] ->
        %URI{uri | query: nil, fragment: nil}

      [name, _subresource] ->
        %URI{uri | path: "/" <> name, query: nil, fragment: nil}
    end
  end

  def instance(%URI{scheme: "system", path: "/" <> rest} = uri) do
    # PR #146 SPEC v2 §5.1 + §5.10 — `system://<type>/<name>` is
    # 2-segment-authority (e.g. `system://routing/default`,
    # `system://bootstrap/default`). Same split as `entity://`.
    case String.split(rest, "/", parts: 2) do
      [_name_only] ->
        %URI{uri | query: nil, fragment: nil}

      [name, _subresource] ->
        %URI{uri | path: "/" <> name, query: nil, fragment: nil}
    end
  end

  def instance(%URI{path: _path} = uri) do
    # Legacy 1-segment-authority schemes (session/workspace/template/
    # resource/message) — entire path is sub-resource. Migrated to the
    # uniform 2-seg target form in PR #147 (query-string action syntax)
    # along with `message://` deletion.
    %URI{uri | path: nil, query: nil, fragment: nil}
  end

  @doc """
  Parse the sub-resource portion of a URI looking for the `behavior/`
  keyword. Returns `{:ok, {behavior_atom, action_atom}}` or
  `{:error, :malformed_path}` (which also covers "this URI's
  sub-resource isn't a behavior call — e.g. it's `/auth/...`").

  **Named parser** — sibling to a hypothetical `auth_action/1`. The
  parser uses `subresource/1` to locate the sub-resource portion
  (positional) and then looks for the `behavior/` prefix within it.

  Examples:
  - `entity://agent/echo_default/behavior/echo/say` → `{:ok, {:echo, :say}}`
  - `entity://agent/cc_demo-builder/behavior/chat/receive` → `{:ok, {:chat, :receive}}`
  - `session://default/main/behavior/chat/send` → `{:ok, {:chat, :send}}`
  - `entity://agent/cc_demo-builder/auth/login` → `{:error, :malformed_path}`
  - `entity://agent/cc_demo-builder` → `{:error, :malformed_path}`
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

  **Positional, uniform** — the mirror image of `instance/1`. Made
  public so future named parsers (e.g. `auth_action/1`) can reuse the
  same split rule without re-deriving it.

  Examples:
  - `entity://user/admin` → `""`
  - `entity://agent/cc_demo-builder/behavior/chat/receive` → `"behavior/chat/receive"`
  - `entity://agent/cc_demo-builder/auth/login` → `"auth/login"`
  - `session://default/main/behavior/chat/send` → `"behavior/chat/send"`
  """
  @spec subresource(URI.t()) :: String.t()
  def subresource(%URI{path: nil}), do: ""

  def subresource(%URI{scheme: "entity", path: "/" <> rest}) do
    # 2-segment authority: name is first segment; remainder is sub.
    case String.split(rest, "/", parts: 2) do
      [_name_only] -> ""
      [_name, sub] -> sub
    end
  end

  def subresource(%URI{scheme: "system", path: "/" <> rest}) do
    # PR #146 — `system://` is 2-segment-authority (same as `entity://`).
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
