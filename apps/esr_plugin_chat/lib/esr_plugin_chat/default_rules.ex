defmodule EsrPluginChat.DefaultRules do
  @moduledoc """
  Phase 3a-step 4: bootstrap idempotent system-default routing rules
  for the chat plugin's RoutingRegistry tables.

  Currently empty — Phase 3 default fan-out (in-session members) is
  implemented as the **fall-through** branch in
  `Esr.Behavior.Chat.invoke(:send, ...)` (per P3-D impl
  default-rules decision (b)) rather than as routing rules. This
  module exists as the canonical insertion point for future
  system-default rules (e.g. audit-fanout, mention-routing-built-ins).

  ## How to bootstrap (future)

      def bootstrap_default_rules do
        if not has_rule?(SomeTable, some_matcher) do
          RuleStore.add(SomeTable, some_matcher, receivers, nil)
        end

        :ok = RuleStore.load_into_registry(SomeTable)
      end

  Called from `EsrPluginChat.Application.start/2` after the
  RoutingRegistry tables are declared.
  """

  alias Esr.Routing.RuleStore
  alias EsrPluginChat.Routing.{MentionRouting, SessionRouting}

  @doc """
  Bootstrap default rules + load any persisted rules from SQLite into
  live RoutingRegistry ETS. Idempotent — safe to call on every boot.
  """
  @spec bootstrap :: :ok
  def bootstrap do
    # Phase 3: no system-default rules to insert (fall-through covers
    # in-session default fan-out). Just hydrate any admin-added rules
    # from SQLite into the live RoutingRegistry ETS tables.
    :ok = RuleStore.load_into_registry(MentionRouting)
    :ok = RuleStore.load_into_registry(SessionRouting)

    :ok
  end
end
