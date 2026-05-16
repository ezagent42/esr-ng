defmodule EsrPluginChat.DefaultRules do
  @moduledoc """
  Phase 4-completion PR 9 §A: declarative default routing rules for the
  chat plugin's RoutingRegistry tables.

  Previously (Phase 3): default fan-out (send to in-session members)
  was hardcoded in `Esr.Behavior.Chat.invoke(:send, ...)` as a
  fall-through branch — a leak per "no scattered routing logic"
  principle (Allen 2026-05-16).

  Now: the default fan-out is **a system_default rule** with magic
  receiver token `"$session_members"` that `Esr.Routing.Resolver`
  expands at resolve time. `/admin/routing` shows it as a real (but
  protected) row.

  ## Bootstrap semantics

  - Per-table idempotent: if `RuleStore.has_system_default?(table)` is
    true → skip (don't double-seed)
  - Admin's delete-then-restart preserved: `delete/1` refuses
    system_default; `disable/1` is the path for admin to opt out
  - `enabled` flag respected by `load_into_registry/1`
  """

  require Logger

  alias Esr.Routing.{Matcher, RuleStore}
  alias EsrPluginChat.Routing.{MentionRouting, SessionRouting}

  @doc """
  Bootstrap default rules + hydrate persisted rules into RoutingRegistry.
  Idempotent — safe to call on every boot.
  """
  @spec bootstrap :: :ok
  def bootstrap do
    :ok = ensure_session_members_default_rule()
    :ok = RuleStore.load_into_registry(MentionRouting)
    :ok = RuleStore.load_into_registry(SessionRouting)
    :ok
  end

  defp ensure_session_members_default_rule do
    if RuleStore.has_system_default?(MentionRouting) do
      :ok
    else
      Logger.info(
        "EsrPluginChat.DefaultRules: seeding system_default rule " <>
          "(always → $session_members) into MentionRouting"
      )

      case RuleStore.add(
             MentionRouting,
             Matcher.always(),
             [Esr.Routing.Resolver.session_members_token()],
             nil,
             source: RuleStore.system_default_source()
           ) do
        {:ok, _row} ->
          :ok

        {:error, reason} ->
          Logger.error(
            "EsrPluginChat.DefaultRules: failed to seed system_default rule: #{inspect(reason)}"
          )

          :ok
      end
    end
  end
end
