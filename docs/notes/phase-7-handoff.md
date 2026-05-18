# Phase 7 handoff — ESR v1 release

> **ESR v1.0** is officially released at Phase 7 closeout. This
> document is the v1 release note + handoff summary for the dev
> team that takes over.

**Released:** 2026-05-18 (Phase 7 closeout, Allen's last hands-on phase).
**Companion docs:** Phase 6 closeout `docs/notes/phase-6-architecture-closeout.md`, SPEC `phase-specs/phase7/SPEC.md` (LOCKED v3), VERIFICATION `phase-specs/phase7/VERIFICATION.md`, PLAN `phase-specs/phase7/PLAN.md`.

---

## v1 in one line

ESR v1 = "production-grade session-template generator" + "complete handoff to dev team without Allen as fallback."

The killer feature is multi-agent orchestration where the user spawns a session, dialogues with its embedded orchestrator agent, and that conversation IS the template-refinement process — outputs (configured agent teams + routing matchers) become first-class persisted `SessionTemplate` rows that can be re-instantiated, forked, version-tagged.

The non-feature half is just as important: invariant tests + an `esr-developer` Claude Code skill take over the architectural-judgment role Allen used to play in PR reviews. Dev team can ship without escalating.

## What v1 actually delivered (8 of the 10 architecturally significant pieces)

| | Decision Log | What it is |
|---|---|---|
| 1 | #135 | `Esr.WorkspaceRegistry` — 5th ETS Registry, fills the session→workspace back-edge gap that silently broke workspace-scoped routing pre-PR-31 |
| 2 | #136 | `AgentTemplate` + `SessionTemplate` are two new Template Class implementations under the existing `Esr.Kind.Template` umbrella in core (no rename / no new namespace needed) |
| 3 | #137 | `Esr.Capability.matches?/2` accepts `{:within_session, %URI{}}` and `{:spawned_by, %URI{}}` instance tuples — **this is the ESR v1 marker**, retiring the v0 "no delegation" baseline (ARCHITECTURE §17.6) |
| 4 | #139 | `mix esr.bootstrap` one-command install + ESR_HOME DB migration mandatory in onboarding |
| 5 | #140 | `esr-developer` Claude Code skill (`.claude/skills/esr-developer/SKILL.md`) is the dev team's "Allen replacement" for architectural judgment, with anti-pattern refusal table |
| 6 | #141 | SessionTemplate fork unit = configuration only (no message history; D7-7) |
| 7 | #142 | Plugin runtime hot-install via `mix esr.plugin.install` (no unload — deferred) |
| 8 | #143 | SessionTemplate version = SHA hash (immutable) + tag overlay (mutable); git-style content addressing |

The two not in this table (#138 Federation drop, #144 cross-PR meta-decision) are framing decisions, not standalone artifacts.

## Three trade-offs the dev team should NOT cargo-cult

These are pragmatic choices made under specific constraints. If the dev team encounters similar shaped problems, **don't auto-apply the same answer** — re-derive the trade-off in the new context.

### 1. `:any` wildcard on cap behavior — *circular-dependency workaround, not idiom*

`Esr.Entity.User.default_caps/0` uses `kind=:session, behavior=:any` for the structural session-chat baseline. The "right" cap would be `behavior: Esr.Behavior.Chat` (specific module). But `Esr.Entity.User` lives in `esr_domain_identity`, and `Esr.Behavior.Chat` lives in `esr_domain_chat`, which already depends on identity → circular dep at compile time.

Choices considered:
- Module reference (correct): requires breaking circular dep (significant refactor)
- Runtime `BehaviorRegistry` lookup: boot-order fragile
- `:any` wildcard: what we did, scoped to a narrow `:kind` so blast radius is one Kind family

**Don't:** copy `:any` into plugin default caps thinking "default caps idiomatically use `:any`." If your plugin can name the specific module without a circular dep, do so.

**When to revisit:** if the dep graph reorganizes (e.g. `Esr.Behavior.Chat` moves to esr_core or somewhere upstream of `esr_domain_identity`), narrow `User.default_caps` to the specific module ref.

### 2. Dispatch mode `:cast` → `:call` override at transport edge

`Esr.Behavior.Chat.@interface[:send]` declares `:send` as `:cast` (fire-and-forget). PR 27 (Feishu inbound) and the orchestrator's tool dispatchers (PR 46) override to `:call` so they can return errors synchronously to the human surface. This is **legitimate** — `Esr.Invocation.dispatch/1` accepts any mode the caller passes.

**Don't:** "fix" a transport from `:cast` to "match the interface declaration" — silent-drop on cap denial is the bug we're avoiding.

**Do:** when adding a new transport for inbound user-driven messages (Slack, Discord, email, etc.), use the same `:call` + error-feedback pattern Feishu's `InboundDispatcher` ships.

### 3. `{:spawned_by, _}` cap shape deny-by-default placeholder

PR 42 ships the contract surface for the `{:spawned_by, principal_uri}` cap shape but returns `false` (denies all matches) until PR 40 ships the `Agent.spawned_by` slice field + lineage lookup registry. This is intentional split — the contract is observable + tested NOW; the data path lands in PR 40 without re-touching `matches?/2`.

**Don't:** assume `{:spawned_by, _}` works as documented in SPEC §D7-3 right now. Check `Esr.Capability.instance_match?/2` source.

**When fixed (PR 40 merged):** verify lineage tests (`cap_scope_spawned_by_test.exs`) pass; verify orchestrator's `grant_cap` tool respects lineage.

## Cross-PR invariants the dev team MUST keep green

Decision #144 names these. Each has a CI gate test:

| Invariant | CI gate |
|---|---|
| Channel `meta` values are all strings | `apps/esr_domain_chat/test/esr/behavior/chat_test.exs` "to_claude payload meta values are all strings" |
| Every user has `session.chat` baseline cap | `apps/esr_domain_identity/test/esr/entity/user_test.exs` `describe "default_caps/0 (PR 27)"` |
| `Chat.invoke(:send)` plumbs workspace_uri to Resolver | `apps/esr_domain_chat/test/integration/workspace_isolation_test.exs` |
| Scope-bounded delegation narrows, never broadens | `apps/esr_core/test/esr/capability_test.exs` "scope-bounded instance tuples" |
| Feishu inbound deny → text + react back, not silent drop | `apps/esr_plugin_feishu/test/feishu_inbound_cap_denial_feedback_test.exs` (TODO if not yet) |
| No `Esr.Bridge.V1Prototype` references in apps/ | `no_v1_bridge_after_cutover_test.exs` (ships with PR 32) |
| ws sidecar reaps on stdin EOF | `apps/esr_plugin_feishu/test/sidecar_orphan_reap_test.exs` |
| Workspace isolation cross-PR | covered by `workspace_isolation_test.exs` (above) |

If any of these fails: **stop the merge**. Do not paper over with a `@tag :skip` — the test is the architectural sensor for one of the decisions Allen would have caught in review.

## What did NOT make v1 (deferred to dev team)

These are out of v1 scope. The dev team picks them up or leaves them based on their own roadmap.

- **CC channel v1→v2 cutover** (PR 32 deferred — see resume note below): v2 BridgeRegistry shipped (Phase 6 PR 4) but `agent://cc-demo` still binds via v1 prototype in production. Cutover requires Python bridge HTTP/SSE → WebSocket port + 6 Elixir file migrations + delete v1 app + invariant test. Risk to Allen's live cc-demo if done carelessly. Allen-flagged "fresh session, careful pre-audit" approach.
- **Federation** (D7-4): Allen reopens later. Not even prep hooks in v1.
- **Plugin unload** (D7-8): hot install ships; unload requires Kind lifecycle management for live instances of the unregistered Kind — non-trivial. Defer until needed.
- **OTP release / Docker / systemd** (D7-9): `mix esr.bootstrap` is sufficient for "dev team installs ESR on prod-like host." Full release engineering when scale demands.
- **SessionTemplate three-way merge** (D7-7): message-tier conflict resolution out of scope.
- **Template synthesis** (orchestrator authoring new AgentTemplates inline): blueprint authoring stays human-only in v1.
- **Cross-session agent delegation**: orchestrator acts within its session scope only.
- **Multimedia / streaming** (Phase 8 — see `IMPLEMENTATION_ROADMAP.md §9c`): Dyte as candidate SFU; control plane stays in ESR (signaling, auth, session, audit); media bytes go to external SFU. Not abstracting a "generic channel" covering both message-passing and streaming.

## Resume / next-session pointers

If this is being read by a Claude Code session picking up Phase 7 work AFTER Allen's involvement (or finishing the deferred items):

1. Start with `docs/notes/phase-7-resume-state.md` for the per-PR status table.
2. Then `phase-specs/phase7/{SPEC,VERIFICATION,PLAN,DECISIONS}.md` for the design.
3. Then this file for the v1 release context.
4. Activate `esr-developer` skill (via Claude Code skill loader) for per-task guidance.
5. Each PR follows the workflow in PLAN.md §per-PR-workflow.

## What "ESR v1" means as a contract to the dev team

A new dev contributor in 2026-06 or later can:

- Clone repo, run `mix esr.bootstrap`, have a working ESR in under 5 minutes
- Open any `.ex` file in the repo and have their Claude Code agent automatically use `esr-developer` skill for architectural guidance
- Refer to `phase-7-handoff.md` (this file) for the v1 release framing
- Refer to ARCHITECTURE Decision Log entries #135-#144 for the design choices
- Refer to GLOSSARY for the 16 new Phase 7 terms
- Refer to CI invariant tests as the architecture sensors
- Hit a tricky bug → find an actionable answer in `docs/runbook/common-failures.md` or the linked forensic note in ≤2 minutes
- Write a new plugin → `mix esr.plugin.install` it into running ESR without phx restart

Allen 2026-05-18: "按照我完全离开 ESR 不管的思路进行规划" — completely-leave assumption is the design constraint behind every Phase 7 choice.

---

## Closing

Allen has driven 7 phases (0-7) plus the Phase 4.5 in-flight insertion, ~30 Decision Log entries (#114-#144 in this span), and the brainstorm history that anchors every "why X" question dev team will ask.

The dev team's job is to take v1, ship the deferred items in their own time, build Phase 8 (or whatever direction makes sense for them), and keep the cross-PR invariants green. The skill + docs + CI are designed to make that possible without Allen on call.

**ESR v1 released.** Phase 7 closed.

— closeout signed off by Allen 2026-05-18, executed by Claude Code (Opus 4.7 / Sonnet 4.7 / Haiku — whichever model picked up the autonomous run).
