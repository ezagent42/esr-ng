# V2 Feedback Log

> **Status**: ACTIVE — V1 acceptance phase begins 2026-05-21. Allen
> manually tests ezagent V1 (Phase 9 closed); Claude records every
> piece of feedback here verbatim + abstracts the essential cause.
>
> When V2 planning begins, this doc is the input source. Don't
> implement during recording.

## Recording protocol

Each piece of feedback gets one entry with **4 fields**:

1. **原始反馈 (Raw quote)** — Allen's exact words from Feishu (Chinese
   preserved verbatim; no paraphrase, no "what Allen meant"). Includes
   timestamp + Feishu message_id when available.
2. **本质原因 (Abstracted root cause)** — what general property of the
   system or interaction is this surfacing? Aim higher than the
   specific bug. "What category of design is wrong?" not "what line
   of code is wrong?"
3. **V2 影响 (V2 implication)** — does this require a SPEC change,
   architectural shift, new abstraction, removed abstraction, or
   just a per-feature fix? Mark scope: structural / tactical /
   ergonomic.
4. **候选方案 (Candidate solutions)** — 1-3 directions, with the
   trade-offs sketched. NOT a decision; that's V2 planning.

Group entries by **theme** (top-level `##` sections). Theme is
derived from feedback content, not pre-committed. Add new themes
as patterns emerge.

## Themes that will appear (initial guesses, adjustable)

- **URI ergonomics** (3-segment is verbose; do users feel the cost?)
- **Workspace switcher UX** (Keycloak model is principled but is it
  intuitive?)
- **Auth flow surface** (workspace param is fiddly; bare-handle vs
  full URI ergonomics)
- **Admin tooling gaps** (manual mix tasks vs LV CRUD; what's
  missing)
- **Session lifecycle** (when sessions persist; rehydration semantics)
- **Plugin authoring friction** (per `feedback_north_star_plugin_isolation`)
- **Multi-agent orchestration UX** (how Phase 7 orchestrator
  surfaces in V1)
- **Demo / first-run experience** (a new dev runs `mix phx.server`
  — what hits them?)
- **Observability gaps** (when things go wrong, can you tell why?)

---

## V2 planning trigger

When Allen says "开始 V2 规划" (or equivalent), this doc becomes
input to a `superpowers:brainstorming` session that produces:

1. `docs/superpowers/specs/<YYYY-MM-DD>-ezagent-v2-charter.md` —
   theme-by-theme synthesis with V2 goals + non-goals
2. Per-theme SPEC drafts following the Phase 9 pattern
3. A revised PR sequence (likely several phases of V2)

Until then: **record, don't implement**.

---

## Entries

## Architecture gap — No auto-trigger from URI registration to associated template instantiate

### 原始反馈

> [Feishu 2026-05-21 16:11 (GMT+9), msg `om_x100b6fdf4c6a08a0c4eaef4621b7af0`]
> 请注意这不是v2内容，而是v1验收没有通过的内容，需要立即dispatch subagent进行修复：
> 1. 请分析会漏instantiate template的根源是什么，目前kind不会自动帮助plugin注入instantiate template这一步吗？
> 2. 之前cc分裂为channel和pty两个部份，现在改为cc-channel启动是本体，可以带with_pty的命令启动本地Pty。这个对出现这个bug有影响吗？
> 3. not running的UI应该如何修改，Domain.Agent是不是应该提供统一的UI，供显示agent的生命周期？

(The surface bug — created cc_demo shows "Not running" — was fixed in V1 (PR #XXX); this entry records the architectural pattern surfaced by Allen's Q1 + Q3.)

### 本质原因

Two related but distinct architectural gaps surfaced by Allen's V1 acceptance testing:

**Gap 1 (Q1)** — There is no **URI-registration → associated-template-instantiate** hook in the Kind / SpawnRegistry layer. Today's flow:
- `SpawnRegistry.spawn(uri)` → starts a Kind process in supervision tree. Done.
- `Workspace.add_template(name, tmpl_name, tmpl)` → updates DB JSON. Done.
- `Workspace.Loader.load_all/0` → iterates all `session_templates` and invokes template's `instantiate/3`. Only runs at **plugin boot** (chat plugin + cc plugin each run it).

Runtime-added templates have nobody calling instantiate. The V1 fix (PR #XXX) puts the invoke inside `Workspace.add_template/3` itself — but that's a tactical wedge, not a structural answer. The deeper question: **should Kind / SpawnRegistry / Template-registration share a generic "post-registration hook" abstraction**? Today each layer (Kind spawn, template add, workspace template list) manages its own side-effects; the chains aren't composable.

**Gap 2 (Q3)** — `AgentDetailLive.load_status/1` directly calls `Ezagent.PluginCc.PtyServer.find_by_agent_uri` — a Domain UI module **importing Plugin module internals**. This violates the 3-tier architecture (invariant 8: plugins extend core, not other way) and means echo/curl agents have no defined "lifecycle status" surface. V1 fix introduces `Ezagent.Domain.Agent.lifecycle_status(uri)` as flavor-agnostic facade; but **Domain.Agent itself is new** — V1 did not have a unified domain model for "agent" across flavors.

Both share: lack of cross-flavor / cross-layer abstractions for agent lifecycle. Each plugin reinvents (cc has PtyServer.find_by_agent_uri; echo has nothing visible; curl has nothing visible).

### V2 影响

- **Scope**: structural — generic Kind-lifecycle hook abstraction; unified Domain.Agent model with lifecycle phases (`:registered → :instantiated → :alive → :busy → :error → :terminated`)
- **Affects**: `Ezagent.Kind`, `Ezagent.SpawnRegistry`, `Ezagent.TemplateRegistry`, new `Ezagent.Domain.Agent`, plugin lifecycle Behavior contracts, all plugin Application boot paths
- **Blocks**: V2 plugin authoring story — without a generic hook + lifecycle behavior, every new plugin has to reinvent both
- **Related Phase 9 PR/SPEC**: this surfaced after Phase 9 closure
- **V1 tactical fix shipped** (PR #XXX): `Workspace.add_template` chains to instantiate; `Ezagent.Domain.Agent.lifecycle_status/1` introduced as flavor-agnostic facade

### 候选方案

- **A — Kind callback `on_spawn_hook/1`**: add to `@behaviour Ezagent.Kind` an optional callback that runs after KindRegistry registration. cc plugin's Agent Kind implements it to start PtyServer. Trade-off: each Kind owns its own bootstrap, but the hook is opt-in so non-running Kinds (echo, system) don't need to implement.
- **B — Template-driven spawn unification**: eliminate "spawn Kind directly" path entirely. ALL agent Kinds must be spawned via a Template; `SpawnRegistry.spawn(entity://agent/...)` is deprecated in favor of `Template.instantiate(template_uri)`. Trade-off: bigger refactor but eliminates the "spawn Kind without template" failure mode.
- **C — Lifecycle Behavior contract**: define `Ezagent.Behavior.Lifecycle` with `phase/2`, `transition/3` actions. Every "running" Kind (agent, session) carries this Behavior. `Ezagent.Domain.Agent.lifecycle_status/1` dispatches `?action=lifecycle.phase` to the Kind. Trade-off: explicit lifecycle modeling vs implicit "is supervisor PID alive" — more code but observable + capability-gated.

Recommended V2: **A + C combo**. A solves the "spawn forgot to instantiate associated template" class. C solves the "UI knows about plugin internals" class. B is too big a refactor for V2 unless multi-flavor agent composition becomes a goal.

### 链接

- V1 tactical fix: PR #XXX (cross-link after merge)
- Same-family pattern in Phase 8c: bare-handle bounce → `SessionPrincipal.put/2` invariant
- Q2 clarification needed from Allen: cc-channel + with_pty mental model vs actual PR-D2 code shape (asked on Feishu 2026-05-21 16:14)
- Test gap: invariant test for "any URI in `session_templates` has a running instantiated process" — missing today, fix to include



### Entry template

```markdown
## <Theme> — <one-line summary>

### 原始反馈

> [Feishu 2026-MM-DD HH:MM, msg `om_xxx`]
> <Allen's exact words, Chinese preserved>

### 本质原因

<1-3 sentences. Not "the button is broken" but "feedback X surfaces
a missing abstraction: the system has no concept of Y, so users have
to do Z manually". Aim higher.>

### V2 影响

- **Scope**: structural | tactical | ergonomic
- **Affects**: <which subsystems / SPEC sections / invariants>
- **Blocks**: <other feedback this depends on, if any>

### 候选方案

- **A**: <approach>; trade-off: <what you give up>
- **B**: <approach>; trade-off: <what you give up>
- **C** (if applicable): <approach>; trade-off: <what you give up>

### 链接

- Related Phase 9 PR/SPEC: <ref if any>
- Related memory: <feedback_xxx if any>
- Related Decision Log entry: #<number> if any
```

---

## Conventions

- **Per memory `feedback_bilingual_docs_convention`**: this doc has a
  `.zh_cn.md` parallel. Both are kept in sync as entries are added.
- **Per memory `feedback_subagent_review_plans`**: when V2 planning
  starts, the SPEC subagent reads BOTH this doc and PHASE 9 SPEC +
  amendments + demo doc.
- **Per memory `feedback_completion_requires_invariant_test`**: V2
  features need invariant tests; this doc identifies what should be
  invariant.
- **No premature implementation**: even if a fix is one-line, record
  it here first. Allen + Claude review the abstraction pass before
  the implementation pass. The point is to find patterns across
  feedback, not to chase individual symptoms.
