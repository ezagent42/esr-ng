# Phase 5 SPEC — architecture alignment review

**Status:** review-loop output; findings folded back into SPEC.md.
**Date:** 2026-05-17.
**Source directive (Allen):** "review spec 是否充分按照 architecture 的思路进行了设计——例如 agent 有没有用起来 template,plugin loader 的操作是否是通过对基础 core 概念(session/entity/resource)进行操作,而非 ad-hoc 的针对具体的 cc agent 等 kind 进行操作"

## Method

Cross-checked SPEC.md draft v1 against:
- `ARCHITECTURE.md` §5.4 (RoutingRegistry responsibility model), §9 (Template double layer Class/Instance), §5.4.7 (4 anti-drift constraints), Decision #112 (boot-ordering pattern)
- `IMPLEMENTATION_ROADMAP.md` §1.3 (8 hard invariants), §8 5a/5b/5c
- Recent Decision Log entries #122-126 (Phase 4.5 PRs)

## 8 drift findings — corrections folded into SPEC.md

### Drift 1 — 5a Feishu binding stored as Workspace.config map (was: ad-hoc)

**Before:** SPEC said "session_feishu_bindings: %{session_uri => chat_id}" lives as a new field in `Workspace.config`.

**Problem:** This is an ad-hoc Workspace.config field for plugin domain knowledge — exactly the pattern §5.4.6 ("core doesn't predefine any table") and Decision #71 (plugin judgement principle) warn against. Workspace becomes Feishu-aware.

**Correction:** introduce **`feishu.chat_binding` Template Class** in `esr_plugin_feishu`. Operator adds binding via the **same** WorkspaceDetailLive add-template form (5d's `form_fields/0` makes this free). On `instantiate/3` the Class:
- Registers `chat_id → session_uri` in plugin-owned `ChatRouting` RoutingRegistry table (per §5.4.4 Phase 1: register)
- Returns the binding's instance URI so it's tracked + removable like any other Template Instance

**Architectural win:** zero new core concept; Feishu binding is "just another Template". 5d's form-fields callback dogfooded.

### Drift 2 — 5a auto-create `user://feishu/<id>` had no Template path

**Before:** "Auto-create on first inbound msg from unknown sender" was a special-case in the webhook receiver.

**Problem:** Side-channel User creation outside the standard SpawnRegistry path; bypasses Identity's spawn invariants (Phase 4.5 PR 2 went through `Esr.SpawnRegistry.spawn/1` for a reason).

**Correction:** Webhook receiver uses `RoutingRegistry.put_new(PrincipalMapping, feishu_user_id, user_uri)` per §5.4.4 — if `:put_new` returns `{:error, :already_exists}` the user is known, if `:ok` we then `SpawnRegistry.spawn(%{kind: :user, uri: ..., args: %{feishu_id: ...}})`. This is the same shape as `user://allen` creation; Feishu users aren't special.

### Drift 3 — 5b cc-channel "register connect token" form (was: bespoke surface)

**Before:** "/admin/cc-channels LV: register connect token + revoke + force-disconnect"

**Problem:** Bespoke LV surface for CC channel state means operators learn two patterns (add-template for cc.pty, separate form for cc.channel). Cognitive cliff.

**Correction:** **`cc.channel_instance` Template Class** — operator registers a CC instance the same way they register a cc.pty agent: WorkspaceDetailLive add-template, select class `cc.channel_instance`, fill form (`agent_uri`, optional `bridge_id_pattern`). The Template's `instantiate/3` mints a connect token, stores it in `credentials/cc-channels.yaml` ($ESR_HOME), exposes it via the Kind's `state_slice` for read-back. Token reveal is a cap-gated Behavior action on the instance, not a separate LV form.

The "/admin/cc-channels" page stays — but it's a **read-only list of CC instance Kinds**, not a CRUD form. Same shape as `/admin/snapshots`.

### Drift 4 — 5c Pty-Web input path risk of bypassing dispatch

**Before:** "input from the browser sends a `Esr.Behavior.Pty.input` invocation back (NOT raw PubSub — invariant #1 hard rule)"

**Status:** Already correct in SPEC — flagged here because it's the easiest invariant to violate at impl time. **Add invariant test** to SPEC: write 100 chars through xterm → assert 100 `:invoke` audit rows present in DB (NOT just on the PtyServer's stdin); if test sees fewer rows the LV hook is bypassing dispatch.

### Drift 5 — 5a "Floating agents" feishu://* entry conflates User Entity with Agent

**Before:** "Floating agents sidebar gets `feishu://*` agents"

**Problem:** Feishu users are Principals (User Kind), not Agents. The sidebar concept is "agents available to add to this session" — Feishu users shouldn't appear there. The actual agent that talks to a Feishu user is the same ESR agent already in the session.

**Correction:** Feishu users appear in **Members panel** (right side, when a session is bound to a Feishu chat) — alongside `user://allen` and `agent://cc-architect`. Their `online` status reflects whether the Feishu user is currently active. They do NOT appear in Floating Agents.

### Drift 6 — Plugin Loader call from new plugins (boot ordering)

**Before:** SPEC didn't mention Decision #112's boot-ordering pattern.

**Problem:** Phase 5 adds 3 plugins (Feishu, cc-channel-v2, Pty-Web). Per Decision #112, each plugin's `Application.start` tail MUST call `Esr.Workspace.Loader.load_all/0` to ensure Template Classes registered by this plugin get to instantiate any pre-existing Workspace bindings on a fresh boot.

**Correction:** SPEC PR plan checklist: every Phase 5 plugin must add this tail call + boot-ordering test (start Workspace with a feishu.chat_binding template BEFORE feishu plugin loads → restart server → assert binding instantiated).

### Drift 7 — 5d `form_fields/0` callback narrow to Template Class only

**Before:** 5d-D1 puts `form_fields/0` on `Esr.Kind.Template` behaviour.

**Problem:** Other LV forms (Users add-cap form from Phase 4.5 PR 2; Routing add-rule from PR 7) also have hand-rolled forms. They'd benefit from the same self-description pattern but won't get it because `form_fields/0` is on the wrong behaviour.

**Correction:** Define `form_fields/0` on a new `Esr.UI.Form` behaviour. Any module — Template Class, Behavior action, Synthetic Kind — implements it to declare its form schema. WorkspaceDetailLive's add-template form is the first consumer; UsersLive's add-cap form is a candidate Phase 5 follow-up consumer.

### Drift 8 — Adapter / core boundary erosion risk in 5a

**Before:** Webhook receiver path was specced as part of `esr_plugin_feishu`, but the LV badge / modal / binding form lives in `esr_web_liveview`.

**Problem:** Adding Feishu-specific code paths into `esr_web_liveview` would create a hard dep between LV and Feishu plugin — exactly the coupling 5d's form_fields is supposed to dissolve.

**Correction:** LV side ONLY consumes `form_fields/0` + generic Template Instance lifecycle (add/remove/inspect). Anything Feishu-specific (chat_id validation, webhook URL, encrypt_key handling) lives in `esr_plugin_feishu` — invoked via the same `Invocation.dispatch` path the form already uses.

## Net architectural shape after corrections

```
esr_plugin_feishu
  ├── Esr.PluginFeishu.Application       — start; register Template Classes; tail Loader.load_all/0
  ├── Esr.PluginFeishu.Template.ChatBinding
  │     @behaviour Esr.Kind.Template
  │     @behaviour Esr.UI.Form           ← new from 5d
  │     instantiate/3 → register session_uri ↔ chat_id in RoutingRegistry
  ├── Esr.PluginFeishu.WebhookPlug       — inbound: lookup session_uri, dispatch
  ├── Esr.PluginFeishu.Bot.Outbound      — outbound: subscribed to session events, calls Python lark client
  └── Esr.PluginFeishu.Behavior.User     — Principal behavior for user://feishu/* (caps)

esr_plugin_cc_channel
  ├── Esr.PluginCcChannel.Application
  ├── Esr.PluginCcChannel.Template.Instance
  │     instantiate/3 → mint connect token, store in $ESR_HOME, spawn ChannelServer Kind
  ├── Esr.PluginCcChannel.ChannelServer  — WS endpoint + per-instance state
  └── Esr.PluginCcChannel.Behavior.Channel — action :revoke / :rotate / :force_disconnect

esr_plugin_pty_web
  ├── EsrWebLiveview.PtyLive              — xterm.js shell
  └── (NO Template — Pty-Web is a view of existing cc.pty Kinds, not new Kinds)

esr_web_liveview (no Feishu/CC knowledge)
  ├── Admin.AddTemplateForm (uses Esr.UI.Form callbacks to render any registered Class)
  └── (existing surfaces unchanged)

esr_core
  └── unchanged + Esr.UI.Form behaviour (3 callbacks; ~25 LOC)
```

**Test of the test:** if Phase 6 wants to add a Slack adapter, the steps are:
1. Write `Esr.PluginSlack.Template.ChannelBinding` (implements Template + UI.Form)
2. Write `Esr.PluginSlack.WebhookPlug` (translates Slack events → Invocation)
3. Done — no LV changes, no core changes, no router changes

If step 3 isn't true, Phase 5 didn't actually deliver the plugin north star.

## Drift-risk inventory (for SPEC + impl PRs)

| # | Risk | Mitigation in SPEC |
|---|---|---|
| R1 | Plugin author adds an LV file in `esr_web_liveview` because the Class form is "almost generic" | SPEC § "Anti-drift checks": grep `apps/esr_web_liveview/lib` for plugin-specific module references; CI fail if any |
| R2 | Webhook receiver bypasses RoutingRegistry "for speed" | Invariant test: webhook → injected event with unknown `chat_id` returns 404 (NOT auto-creates a session) |
| R3 | CC channel reuses Phase 1 v1_prototype HTTP routes | Mark v1 routes as deprecated; new plugin uses Phoenix.Channel handshake (per Roadmap §1.3 invariant #8 + §8 5b) |
| R4 | Pty-Web hook writes to PubSub topic directly to skip dispatch overhead | Invariant test from Drift 4 above |
| R5 | feishu.user creation bypasses SpawnRegistry | Per-spawn-path audit test; SpawnRegistry is single source of truth for Kind birth |
| R6 | Form schema introduces 10 field types because "Feishu needs `chat_picker`" | 5d-D2 freezes to 4 field types in v1; new types need a Decision Log entry |
| R7 | ESR_HOME becomes a second source of truth for state currently in SQLite | ESR_HOME holds **credentials + boot-time bindings + ops files** only; runtime state stays in SQLite. Drift detector: any new `File.write!` in plugin runtime path needs review |

## Recommended PR sequencing (replaces SPEC v1 plan)

5d is the meta-enabler; Feishu is the validator. Order:

| PR | Theme | Why this slot |
|---|---|---|
| 1 | ESR_HOME + `mix esr.home.init` + `mix esr.home.import_from_esrd_dev` | Credentials home; 5a can't ship without it |
| 2 | `Esr.UI.Form` behaviour + dynamic WorkspaceDetailLive add-template form (5d) | Meta-enabler; 3-6 dogfood it |
| 3 | `/admin/agents/:uri` PTY status LV (5d) | Operational visibility; doesn't depend on 4-6 |
| 4 | Pty-Web xterm.js (5c) | First non-trivial consumer of dynamic form (pty target picker) + first invariant test that input goes through dispatch |
| 5 | `esr_plugin_cc_channel` Template Class + ChannelServer Kind (5b) | First plugin to use the new architectural shape end-to-end; v1_prototype stays running in parallel |
| 6 | `esr_plugin_feishu` (Template Class for chat_binding + WebhookPlug + Python bot port) (5a) | **Final validator**: if 5a lands without LV changes / core changes / router changes (beyond webhook route registration), Phase 5 succeeded the north star test |

## Answer to ESR_HOME-Q1 / Q2 / Q3 + open Phase 5 questions

Tracked in `ESR_HOME.md` and SPEC.md Open Questions section.

## Closing

Drift findings 1-3 + 6-8 are **architectural** — they would have caused real coupling. Findings 4-5 are **implementation-time guards** that need invariant tests.

This review is what should have happened *before* the Phase 4.5 mis-naming too. Memory `feedback_phase_planning_reads_main_docs` now captures the rule.
