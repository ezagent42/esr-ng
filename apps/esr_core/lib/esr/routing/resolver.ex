defmodule Esr.Routing.Resolver do
  @moduledoc """
  Resolver — given a `%Esr.Message{}` + the current Session URI,
  derives the **cross-session** recipient list by querying
  `RoutingRegistry` tables and matching rules against the message.

  Per DECISIONS P3-D impl Resolver-Matcher interface:
  - Signature: `resolve(message, current_session_uri) :: [recipient_uri]`
  - Hard-codes the table query order: `MentionRouting` + `SessionRouting`
    (Phase 3 scope; Phase 4+ may make table list configurable)
  - **Returns `[]`** when no rule matches — caller (`Chat.invoke(:send)`)
    falls through to in-session default fan-out (current session members
    minus sender). Per P3-D impl default-rules decision (b).
  - Additive semantics: a Message that matches N rules collects union
    of all their receivers (Decision #41)
  - Receivers in rules are URI strings (per RuleStore JSON storage);
    Resolver parses to `%URI{}` before returning

  ## Why two table queries?

  - `MentionRouting`: matcher-keyed,value = `[session_uri]` —
    triggered by message-content match (e.g. `@oncall` → oncall session)
  - `SessionRouting`: bridge_id-keyed,value = session_uri —
    triggered at bridge attach for "where does this bridge default into"
    (Phase 3 routes to admin's "Add to session" event; not directly
    consumed by `Resolver` in the Phase 3 demo flow). Read by Resolver
    so future bridge-side-policy routing extensions land here.
  """

  alias Esr.{Message, RoutingRegistry}
  alias Esr.Routing.Matcher

  @default_routing_tables [
    EsrPluginChat.Routing.MentionRouting,
    EsrPluginChat.Routing.SessionRouting
  ]

  @doc """
  Resolve recipients for `message` in context of `current_session_uri`.

  Returns a deduplicated list of recipient URI structs. Empty list
  means "no routing rule fired — caller should fall through to
  in-session default fan-out".

  Table list is read from `Application.get_env(:esr_core, :routing_tables,
  @default_routing_tables)` so tests can override without conflicting
  with the live chat plugin's owned tables.
  """
  @spec resolve(Message.t(), URI.t()) :: [URI.t()]
  def resolve(%Message{} = message, %URI{} = _current_session_uri) do
    Application.get_env(:esr_core, :routing_tables, @default_routing_tables)
    |> Enum.flat_map(&query_table(&1, message))
    |> Enum.uniq()
    |> Enum.map(&parse_uri_string/1)
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
          # Receivers stored as list-of-strings in RuleStore;
          # RoutingRegistry value is that list.
          List.wrap(receivers)
        end)
    end
  end

  # If table not declared (e.g. test env without plugin started), skip silently.
  defp safe_list_all(table_name) do
    try do
      RoutingRegistry.list_all(table_name)
    rescue
      ArgumentError -> []
    end
  end

  defp parse_uri_string(s) when is_binary(s), do: URI.new!(s)
  defp parse_uri_string(%URI{} = u), do: u
end
