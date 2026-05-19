defmodule Ezagent.URI do
  @moduledoc """
  URI helpers — thin convenience over stdlib `URI`.

  ## Shape (SPEC v2 — PR #141 onwards, query-string actions since #148)

  SPEC v2 §5.1 defines the **target** uniform 2-segment authority
  for every Ezagent URI:

      <scheme>://<type>/<name>[/<sub-resource>...][?action=<behavior>.<action>]

  - `<scheme>` is one of the registered schemes (see
    `Ezagent.URI.SchemeRegistry` — runtime ETS allowlist, PR #145).
  - `<type>` is the value on the scheme's type axis (e.g. `user` /
    `agent` for `entity://`, free-form tenant name for `workspace://`).
  - `<name>` is the instance identity within `<scheme>/<type>`.
  - Anything after `/<name>` is sub-resource (reserved for future named
    sub-resources such as `/auth/...`; the previous path-based
    `/behavior/<kind>/<action>` suffix was removed in PR #148,
    SPEC v2 §5.2).
  - `?action=<behavior>.<action>` selects the Behavior + action to invoke
    (SPEC v2 §5.2, PR #148). The path is identity; the query carries the
    action verb.

  PR #148 (SPEC v2 §5.2) moved action selection from a path suffix to a
  query parameter:

      OLD: entity://agent/cc_demo-builder + path suffix selecting behavior+action
      NEW: entity://agent/cc_demo-builder?action=chat.receive

  ### Examples

      entity://user/admin                                   # bare instance
      entity://agent/cc_demo-builder?action=chat.receive    # action dispatch
      session://default/main?action=chat.send
      workspace://default/main?action=routing.add_rule
      template://agent/cc-orchestrator
      system://routing/default?action=add_rule

  ## SPEC v2 deltas

  - `user://` + `agent://` schemes deleted — merged into `entity://` (PR #141).
  - `instance/1` strips query + fragment + (legacy) trailing path segments.
  - `behavior_action/1` reads `?action=<behavior>.<action>` (PR #148).
  - Agent flavor (cc / curl / echo) moves OUT of the URI type segment
    INTO the name segment as a free-form prefix:
    `entity://agent/cc_demo-builder`, `entity://agent/curl_my-deepseek`
    (SPEC §5.14).

  ## Parser layering

  - `instance/1` is **positional**: it knows where the instance ends
    based on uniform structure (always `host + /first-path-segment`),
    NOT by searching for a keyword like "behavior".
  - `behavior_action/1` is **named**: it pulls the `action` query param
    and splits it on `.` into `{behavior_atom, action_atom}`. A future
    `auth_action/1` could do the same for an `auth=` query param.

  ## Scheme allowlist — runtime ETS (PR #145)

  The set of accepted schemes is the live `Ezagent.URI.SchemeRegistry`
  ETS table, NOT a compile-time list. Plugins extend it only via
  `Ezagent.SpawnRegistry.register/2` (which co-registers).

  Boot-time seeded schemes (SPEC §5.6):
  `entity`, `workspace`, `session`, `template`, `resource`, `system`.

  Deleted (rejected by `parse!/1`):
  - `user`, `agent` (PR #141 — merged into `entity://`)
  - `feishu` (PR #143 — plugin re-shaped, SPEC §5.8)
  - `routing-admin`, `pty-input` (PR #144 — synthetic singletons
    dissolved per SPEC §5.7)
  - `message` (PR #145 — `Ezagent.Message.uri` renamed `id`, SPEC §5.13)
  """

  @doc """
  Parse a binary URI into a stdlib `%URI{}`. Raises on malformed input
  (let-it-crash — adapter is responsible for clean URIs).

  Rejects any scheme not registered in `Ezagent.URI.SchemeRegistry` —
  the SPEC v2 §5.11 lockdown that prevents documentation-drift bugs
  like the deleted-but-still-accepted `feishu://` scheme.
  """
  @spec parse!(String.t()) :: URI.t()
  def parse!(s) when is_binary(s) do
    case URI.new(s) do
      {:ok, %URI{scheme: nil}} ->
        raise ArgumentError, "URI missing scheme: #{inspect(s)}"

      {:ok, %URI{scheme: scheme} = u} ->
        if Ezagent.URI.SchemeRegistry.registered?(scheme) do
          u
        else
          raise ArgumentError,
                "URI scheme #{inspect(scheme)} not registered. " <>
                  "Known: #{inspect(Ezagent.URI.SchemeRegistry.list_all())}"
        end

      {:error, part} ->
        raise ArgumentError, "URI parse failed at #{inspect(part)}: #{inspect(s)}"
    end
  end

  @doc """
  Return the instance form of a URI — drop query + fragment and (for
  legacy 1-seg schemes) any trailing sub-resource path segments.

  Under SPEC v2 §5.2 (PR #148), the action verb lives in the query
  string, NOT in the path. So instance/1 mostly just strips
  `query` + `fragment`. Path is the identity.

  **2-segment-authority schemes** (`entity://`, `system://`) keep the
  `host + /<first-path-segment>` split — if any trailing path segments
  exist (reserved for future named sub-resources like `/auth/login`),
  they are stripped.

  **Legacy 1-seg-authority schemes** (`session://`, `workspace://`,
  `template://`, `resource://`) drop the entire path to recover the
  bare instance form. Migration to uniform 2-seg lives in a future PR.

  Examples:
  - `entity://user/admin` → unchanged (no sub-resource, no query)
  - `entity://agent/cc_demo-builder?action=chat.receive`
    → `%URI{scheme: "entity", host: "agent", path: "/cc_demo-builder"}`
  - `system://routing/default?action=add_rule`
    → `%URI{scheme: "system", host: "routing", path: "/default"}`
  - `session://main?action=chat.send`
    → `%URI{scheme: "session", host: "main", path: nil}` (legacy
       1-seg session URI; path stripped entirely)
  - `workspace://default/main?action=routing.add_rule`
    → `%URI{scheme: "workspace", host: "default", path: nil}` (legacy
       1-seg)
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
  Parse the `?action=<behavior>.<action>` query parameter of a URI.
  Returns `{:ok, {behavior_atom, action_atom}}` or
  `{:error, :missing_action | :malformed_action}`.

  **PR #148 SPEC v2 §5.2** — action selection moved from the path
  suffix (`/behavior/<kind>/<action>`) to a query parameter. Path is
  identity; query carries the action verb.

  **Named parser** — sibling to a hypothetical `auth_action/1` that
  would read a different query key. Each named parser reads its own
  key and converts the value (e.g. dotted form for action+behavior).

  Examples:
  - `entity://agent/echo_default?action=echo.say` → `{:ok, {:echo, :say}}`
  - `entity://agent/cc_demo-builder?action=chat.receive` → `{:ok, {:chat, :receive}}`
  - `session://default/main?action=chat.send` → `{:ok, {:chat, :send}}`
  - `entity://agent/cc_demo-builder` → `{:error, :missing_action}`
  - `entity://agent/cc_demo-builder?action=` → `{:error, :missing_action}`
  - `entity://agent/cc_demo-builder?action=justone` → `{:error, :malformed_action}`
  """
  @spec behavior_action(URI.t()) ::
          {:ok, {atom(), atom()}} | {:error, :missing_action | :malformed_action}
  def behavior_action(%URI{query: query}) when is_binary(query) do
    decoded = URI.decode_query(query)

    case Map.get(decoded, "action") do
      nil ->
        {:error, :missing_action}

      "" ->
        {:error, :missing_action}

      action_str ->
        case String.split(action_str, ".", parts: 2) do
          [behavior, action] when behavior != "" and action != "" ->
            {:ok, {String.to_atom(behavior), String.to_atom(action)}}

          _ ->
            {:error, :malformed_action}
        end
    end
  end

  def behavior_action(_), do: {:error, :missing_action}

  @doc """
  Return the sub-resource portion of a URI as a string (no leading
  slash), or `""` if there is none.

  **Positional, uniform** — the mirror image of `instance/1`. Made
  public so future named parsers (e.g. `auth_action/1`) can reuse the
  same split rule without re-deriving it.

  Examples:
  - `entity://user/admin` → `""`
  - `entity://agent/cc_demo-builder?action=chat.receive` → `"behavior/chat/receive"`
  - `entity://agent/cc_demo-builder/auth/login` → `"auth/login"`
  - `session://default/main?action=chat.send` → `"behavior/chat/send"`
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

  @doc """
  Known scheme allowlist — delegates to `Ezagent.URI.SchemeRegistry.list_all/0`
  (runtime ETS, PR #145). Returns the live set so diagnostics + tests
  reflect plugin-added schemes (e.g. those registered via
  `Ezagent.SpawnRegistry.register/2`).
  """
  @spec known_schemes() :: [String.t()]
  def known_schemes, do: Ezagent.URI.SchemeRegistry.list_all()
end
