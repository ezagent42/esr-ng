# SPEC review checklist

**When to use:** every per-phase SPEC (and per-PR SPEC for cross-cutting changes) MUST be walked through this checklist by the reviewer (Allen) **or** by a code-reviewer subagent (per memory `feedback_subagent_review_plans`) BEFORE implementation begins.

The checklist is short on purpose. Each item maps to a real lesson incident in our git history.

## A. Architecture alignment

A1. **Does this SPEC reference IMPLEMENTATION_ROADMAP.md §N for its phase number?**
- If no: stop. Read the roadmap first. Mis-naming Phase 5 as "operator-tool maturity" instead of "Feishu+CC+Pty-Web" cost a rename PR (2026-05-17, memory `feedback_phase_planning_reads_main_docs`)

A2. **Does this SPEC reference relevant ARCHITECTURE.md sections?**
- §5.4.4 RoutingRegistry responsibility (for any routing change)
- §5.5 additive rules (for any matcher change)
- §9 Template double-layer (for any Class/Instance change)
- §17 deferred (don't accidentally re-spec something Allen has parked)

A3. **Does this SPEC list relevant Decision Log entries?**
- Greppable: `Decision #NN` in ARCHITECTURE.md
- If the SPEC touches Kind lifecycle / CapBAC / Snapshot / RoutingRegistry, cite the decisions that govern those areas

## B. Plugin shape (for plugin-introducing SPECs)

B1. **For external-integration plugins (Feishu, Slack, Discord, email, webhook, ...): is the external destination modeled as a Receiver Kind?**
- See `docs/notes/plugin-receiver-kind-contract.md`
- If SPEC includes "subscribe to `chat_message` PubSub" + "make HTTP call in handler" → STOP. Rewrite as Kind + Behavior + routing rule
- Failed example: Phase 5 PR 6 first impl (`EsrPluginFeishu.OutboundSubscriber`). Cost a Plan B refactor PR (2026-05-17, memory `feedback_plugin_external_integration_is_receiver_kind`)

B2. **Does the plugin Application.start register everything in the right order?**
- Per Decision #112: `SpawnRegistry.register("<scheme>")` + `BehaviorRegistry.register(Kind, action, Behavior)` + Template.register + `Esr.Workspace.Loader.load_all/0` at the tail
- If plugin's Templates depend on other plugins (e.g. Feishu depends on chat's MentionRouting table), ensure the load_all re-run picks them up

B3. **Does the SPEC declare what's stored where?**
- SQLite (durable, queryable, runtime state)
- ESR_HOME files (credentials, boot-time-only config)
- ETS (RoutingRegistry tables, snapshots)
- GenServer state (ephemeral runtime)
- Conflating these wastes review time and invites data-loss bugs later

## C. Invariant tests

C1. **Does each PR in the plan have an invariant test?** (memory `feedback_completion_requires_invariant_test`)
- The test should fail if the architectural goal is unmet
- "Implementation passes unit tests + LV renders" is not the same gate

C2. **Is the invariant test phrased structurally?**
- Bad: "send msg → Feishu receives" (network-dependent, brittle)
- Good: "send msg → audit row count == external write count" (structural — bypasses fail this)

## D. User-assist steps

D1. **Are all user-assist steps flagged?** (memory `feedback_flag_user_assist_steps`)
- Operator provisioning credentials
- External system console config (Feishu webhook URL etc)
- Real-system integration test that I can't run AFK

D2. **What's the AFK-safe demo path?**
- Can the demo run end-to-end without human action mid-flow?
- If not, flag exactly which steps need Allen + scope so demo is verifiable when he wakes

## E. Drift defenses

E1. **Does this SPEC introduce a new abstraction layer or a new mechanism?**
- New abstraction → memory `feedback_let_it_crash_no_workarounds` applies; consider whether existing primitives express the goal
- New mechanism → must add to GLOSSARY.md + Decision Log

E2. **Will the CI invariant tests (`mix test`) catch a regression of this SPEC's goal?**
- Layer 2 CI gates: routing_consolidation_invariant_test (Phase 4.5 PR 9), receiver_kind_pattern_test (Phase 5 Plan B)
- If new SPEC introduces a similar "easy to bypass" risk, add a similar CI gate

## How to use

- Before any /goal implementation, walk through A-E aloud (or have code-reviewer subagent walk through it)
- Document the answers inline in the SPEC under a `## SPEC_REVIEW` section
- Allen reads the SPEC_REVIEW section first to find anything missed
- Each NO answer is either fixed or explicitly accepted with rationale

This document is intentionally short. If the checklist grows past 1 page, it stops being read.
