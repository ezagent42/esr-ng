# Plugin Receiver Kind contract

**Status:** normative (Allen 2026-05-17). Any plugin author or `/goal` agent introducing an external integration MUST follow this contract.

## The rule

Any plugin that sends messages OUT of Ezagent to an external system (Feishu, Slack, Discord, email, webhook, ...) MUST model the external destination as a **Receiver Kind** with a `:receive` action Behavior, routed by a routing rule.

## What "Receiver Kind" means

1. **Kind module** — defines URI scheme + `Ezagent.Kind` callbacks
   - `type_name/0` → atom identifier (e.g. `:feishu_chat`)
   - `behaviors/0` → `[YourBehaviorModule]`
   - `persistence/0` → typically `:ephemeral`
   - `uri_from_args/1` → extracts URI from spawn args
   - Optional helper: `uri_for(external_id) :: URI.t()` and `<external_id>_from_uri(uri) :: String.t()`

2. **Behavior module** — implements `Ezagent.Behavior` with at least `:receive`
   - Same shape as `Ezagent.Behavior.Chat.invoke(:receive, ...)` so the existing dispatch path in chat plugin reaches it transparently
   - External API call happens inside `invoke(:receive, ...)`
   - Self-echo prevention: skip if `msg.sender` is a URI scheme this plugin owns (e.g. `user://feishu/*` for Feishu inbound)

3. **Application.start registers** in this order:
   - `Ezagent.SpawnRegistry.register("<scheme>", fn uri -> DynamicSupervisor.start_child(your_sup, {Ezagent.Kind.Server, {YourKind, %{uri: uri}}}) end)`
   - For each Behavior action: `Ezagent.BehaviorRegistry.register(YourKind, action, YourBehavior)`

4. **Routing rule** — binds external destinations to sessions
   - Use `Ezagent.Routing.Matcher.in_session(session_uri)` to scope rules per-session (otherwise rules fire globally)
   - Add via `Ezagent.Routing.RuleStore.add(MentionRouting, matcher, [receiver_uri], nil, source: admin_source())`
   - Re-load registry: `RuleStore.load_into_registry(MentionRouting)`

## What is FORBIDDEN

**Subscribing to session PubSub topics from a plugin GenServer and emitting externally in `handle_info`:**

```elixir
# ❌ FORBIDDEN
defmodule MyPlugin.OutboundSubscriber do
  def init(_) do
    Phoenix.PubSub.subscribe(EzagentCore.PubSub, "esr:session:" <> sess <> ":events")
    {:ok, %{}}
  end

  def handle_info({:chat_message, _session, msg}, state) do
    MyPlugin.Client.send_to_external(msg.body.text)  # bypasses dispatch + audit + cap
    {:noreply, state}
  end
end
```

Why forbidden:
- Bypasses `Ezagent.Invocation.dispatch` — no CapBAC check, no audit row
- Bypasses Resolver — routing logic is invisible in `routing_rules` table
- Bypasses idempotency / ready-gate
- Same-name users in different sessions cannot be disambiguated downstream
- Breaks the invariant `audit_row_count == external_side_effect_count`

## What IS allowed for subscribing

Subscribing is legitimate for **view fan-outs** that don't produce external side effects:
- LiveView streams (admin /audit, /agents views)
- In-process logging/metrics
- Observers that update internal state only

Test for "is this subscribing OK?": *if I disconnect the subscriber, does an external system stop receiving updates?* If yes → forbidden (use Receiver Kind). If no (just an in-process observer) → OK.

## Reference implementation

`apps/ezagent_plugin_feishu/` — the canonical Receiver Kind plugin:
- `Ezagent.Entity.FeishuChat` (Kind, `feishu://oc_xxx`)
- `EzagentPluginFeishu.Behavior.FeishuReceive` (Behavior, `:receive` calls lark)
- `EzagentPluginFeishu.Application` (registers SpawnRegistry + BehaviorRegistry)
- `Ezagent.Template.FeishuChatBinding` (Template Class — operator-facing entry point that spawns the Kind + adds the routing rule)

## CI invariant (planned, Layer 2)

A future `routing_dispatch_only_invariant_test.exs` will grep plugin source for:
- `Phoenix.PubSub.subscribe` with `chat_message` pattern
- HTTP/file write APIs in `handle_info`
- Flag combinations as "review needed; should this be a Receiver Kind?"

Until that lands, this contract is enforced by code review + the memory `feedback_plugin_external_integration_is_receiver_kind`.

## Lesson (2026-05-17)

Phase 5 PR 6 first impl used the forbidden pattern (`OutboundSubscriber`). Worked but ARCH-misaligned. Plan B PR refactored to Receiver Kind shape. This document and the memory are the second-line defense against the same drift recurring.
