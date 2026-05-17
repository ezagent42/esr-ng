defmodule Esr.Routing.Resolver do
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

  alias Esr.{Message, RoutingRegistry}
  alias Esr.Routing.Matcher

  @default_routing_tables [
    EsrDomainChat.Routing.MentionRouting,
    EsrDomainChat.Routing.SessionRouting
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
    Application.get_env(:esr_core, :routing_tables, @default_routing_tables)
    |> Enum.flat_map(&query_table(&1, message))
    |> Enum.flat_map(&expand_receiver(&1, message, current_session_uri, members))
    |> Enum.uniq_by(&URI.to_string/1)
    |> Enum.reject(&(URI.to_string(&1) == URI.to_string(current_session_uri)))
  end

  # Backward-compat shim: old 2-arg form, members default to []. Phase 4
  # callers must pass members explicitly; this clause exists for
  # transitional callers + tests that don't need member fan-out.
  @spec resolve(Message.t(), URI.t()) :: [URI.t()]
  def resolve(%Message{} = message, %URI{} = current_session_uri) do
    resolve(message, current_session_uri, [])
  end

  defp query_table(table_name, message) do
    case safe_list_all(table_name) do
      [] ->
        []

      rows ->
        rows
        |> Enum.filter(fn {matcher_tuple, _receivers} ->
          Matcher.match?(matcher_tuple, message)
        end)
        |> Enum.flat_map(fn {_matcher, receivers} ->
          List.wrap(receivers)
        end)
    end
  end

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
