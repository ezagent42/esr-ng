defmodule Ezagent.Routing.Resolver do
  @moduledoc """
  Resolver — single source of truth for routing decisions (Phase 4-completion
  PR 9 consolidation).

  Per Decision #41 (additive rules), #97 (cross-session + in-session
  fall-through), and Phase 4-completion §A (no hidden fan-out in
  Behavior code):

  - `resolve/3` takes a Message + current session URI + members list
    and returns the COMPLETE recipient list — `Chat.invoke(:send)`
    must call this and dispatch to whatever it returns, **nothing
    more**. No hardcoded fan-out in Behavior code.
  - All routing logic (mention-based / from-based / always / combinators
    / in-session-member fan-out) is expressible as RoutingRegistry
    rules. The previously-hardcoded in-session fan-out is now a
    `system_default` rule with `receivers: ["$session_members"]` — a
    magic token Resolver expands at resolve time using the `members`
    arg.

  ## Magic receiver tokens

  - `"$session_members"` — expands to the current session's members
    list (excluding the message sender) — replaces the old hardcoded
    fan-out in `Chat.invoke(:send)`.

  Magic tokens are surface to LV `/admin/routing` editor as
  human-readable "(dynamic: ...)" entries so operators see the full
  effective routing.

  ## Why `members` is passed as arg (not computed via :sys.get_state)

  `Chat.invoke(:send)` has the slice in hand — passing members avoids
  a synchronous call into the Session's mailbox. Resolver stays a
  pure function over (msg, session_uri, members) → recipients.
  """

  alias Ezagent.{Message, RoutingRegistry}
  alias Ezagent.Routing.Matcher

  @default_routing_tables [
    EzagentDomainChat.Routing.MentionRouting,
    EzagentDomainChat.Routing.SessionRouting
  ]

  @session_members_token "$session_members"

  @doc """
  Magic token signaling "expand to current session's members" in a
  rule's receivers list. Surface in LV / mix CLI for discoverability.
  """
  def session_members_token, do: @session_members_token

  @doc """
  Resolve recipients for `message` in context of `current_session_uri`
  with the session's `members` list.

  Returns a deduplicated `[URI.t()]` of all recipients (cross-session
  routes + in-session members from magic tokens). Sender is excluded
  in the magic-token expansion to prevent self-receive.

  This is the SINGLE call site Chat.invoke(:send) should use. If you
  find yourself adding "in-session fan-out" or other recipient logic
  inside a Behavior, that's a leak — express it as a routing rule
  instead (or extend the magic token vocabulary here).
  """
  @spec resolve(Message.t(), URI.t(), [URI.t()]) :: [URI.t()]
  def resolve(%Message{} = message, %URI{} = current_session_uri, members)
      when is_list(members) do
    resolve(message, current_session_uri, members, [])
  end

  # Backward-compat shim: old 2-arg form, members default to []. Phase 4
  # callers must pass members explicitly; this clause exists for
  # transitional callers + tests that don't need member fan-out.
  @spec resolve(Message.t(), URI.t()) :: [URI.t()]
  def resolve(%Message{} = message, %URI{} = current_session_uri) do
    resolve(message, current_session_uri, [], [])
  end

  @doc """
  Phase 6 PR 8: 4-arg form with workspace-scope context.

  `opts`:
    * `:workspace_uri` — current Session's owning workspace URI (or nil
      for sessions not bound to a workspace). Rules with a non-nil
      `workspace_uri` only fire if it matches the context; rules with
      `nil` workspace_uri apply globally.

  Use this from `EzagentDomainChat.Behavior.Chat.invoke(:send)` when the
  Session knows its workspace binding. Old 3-arg call sites continue
  to work — workspace scoping passes through as nil = global-only
  rules apply.
  """
  @spec resolve(Message.t(), URI.t(), [URI.t()], keyword()) :: [URI.t()]
  def resolve(%Message{} = message, %URI{} = current_session_uri, members, opts)
      when is_list(members) and is_list(opts) do
    workspace_uri = Keyword.get(opts, :workspace_uri) |> uri_to_string()

    Application.get_env(:ezagent_core, :routing_tables, @default_routing_tables)
    |> Enum.flat_map(&query_table(&1, message, workspace_uri))
    |> Enum.flat_map(&expand_receiver(&1, message, current_session_uri, members))
    |> Enum.uniq_by(&URI.to_string/1)
    |> Enum.reject(&(URI.to_string(&1) == URI.to_string(current_session_uri)))
  end

  defp query_table(table_name, message, workspace_uri_str) do
    case safe_list_all(table_name) do
      [] ->
        []

      rows ->
        sender_str = uri_to_string(message.sender)

        rows
        |> Enum.filter(fn {matcher_tuple, _value} ->
          Matcher.match?(matcher_tuple, message)
        end)
        |> Enum.filter(fn {_matcher, value} ->
          applies_to_sender?(value, sender_str)
        end)
        |> Enum.filter(fn {_matcher, value} ->
          applies_to_workspace?(value, workspace_uri_str)
        end)
        |> Enum.flat_map(fn {_matcher, value} ->
          receivers_of(value)
        end)
    end
  end

  # Phase 6 PR 5: rule value shape is either a plain list (legacy:
  # `[receiver_str, ...]`) or a map with `:receivers` + `:applies_to_users`.
  # Plain list path is for ETS entries written directly via
  # `RoutingRegistry.put` (tests, hand-coded callers) — they have no
  # user filter so always apply.
  defp receivers_of(receivers) when is_list(receivers), do: receivers
  defp receivers_of(%{receivers: receivers}), do: receivers

  defp applies_to_sender?(value, _sender) when is_list(value), do: true
  defp applies_to_sender?(%{applies_to_users: []}, _sender), do: true

  defp applies_to_sender?(%{applies_to_users: users}, sender_str)
       when is_list(users),
       do: sender_str in users

  defp applies_to_sender?(_value, _sender), do: true

  # Phase 6 PR 8 — workspace scope filter.
  # nil context = no workspace binding → only nil-scoped rules apply.
  # non-nil context = rule applies if its workspace_uri is nil (global)
  # OR matches the context exactly.
  defp applies_to_workspace?(value, _ctx) when is_list(value), do: true
  defp applies_to_workspace?(%{workspace_uri: nil}, _ctx), do: true
  defp applies_to_workspace?(%{workspace_uri: same}, same), do: true
  defp applies_to_workspace?(%{workspace_uri: _}, _other), do: false
  defp applies_to_workspace?(_value, _ctx), do: true

  defp uri_to_string(nil), do: nil
  defp uri_to_string(%URI{} = u), do: URI.to_string(u)
  defp uri_to_string(s) when is_binary(s), do: s

  defp safe_list_all(table_name) do
    try do
      RoutingRegistry.list_all(table_name)
    rescue
      ArgumentError -> []
    end
  end

  # Expand magic tokens. Receivers are stored as binaries in RuleStore;
  # the magic token "$session_members" expands via the `members` arg.
  defp expand_receiver(@session_members_token, message, _current_session_uri, members) do
    sender_str =
      case message.sender do
        %URI{} = u -> URI.to_string(u)
        s when is_binary(s) -> s
      end

    members
    |> Enum.reject(fn m -> URI.to_string(m) == sender_str end)
  end

  defp expand_receiver(receiver, _message, _current, _members)
       when is_binary(receiver),
       do: [URI.new!(receiver)]

  defp expand_receiver(%URI{} = receiver, _message, _current, _members),
    do: [receiver]
end
