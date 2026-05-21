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

## Workflow gap — UI "create agent" verb hides the instantiate step

### 原始反馈

> [Feishu 2026-05-21 15:59 (GMT+9), msg `om_x100b6fde9bf484a8c4afee8c48a8120`]
> 我刚创建了 Agent: entity://agent/default/cc_demo，但看起来还是显示not running, 请检查是否已经启动？如果没有，为什么？如果启动了，为什么显示not running?

### 本质原因

User-facing verb **"create agent"** in V1 does NOT equal **"agent ready to receive messages"**. The UI flow splits "create" into 3 internal steps (spawn Kind into supervisor + add cc.agent template to workspace.session_templates JSON + start PtyServer via `cc.agent.instantiate/3`) but `AgentNewLive.handle_event("create_agent")` only does steps 1 + 2. Step 3 (PtyServer start) only happens via `Workspace.Loader.load_all/0` which runs at phx boot — so newly-created cc agents are not running until the next phx restart.

This is the same abstraction-leak family as the **Phase 8c bare-handle bounce** bug (where the auth verb's apparent effect diverged from what got stored in session). Both share the pattern: a user-facing verb whose dispatch path is structurally incomplete relative to the verb's apparent meaning.

### V2 影响

- **Scope**: structural — V1's `AgentNewLive` "create" verb is misleading; deeper than a one-line fix
- **Affects**: `EzagentPluginLiveview.AgentNewLive`, `Ezagent.Workspace.Loader`, `Ezagent.PluginCc.PtyServer` lifecycle, possibly the abstraction of "agent kind lifecycle phases" itself
- **Blocks**: Allen's V1 acceptance testing of cc agents (workaround: phx restart) — not a hard block on continuing other testing
- **Related Phase 9 PR/SPEC**: none directly; this is a Phase 8c surface bug surfaced by V1 testing
- **Related memory**: similar shape to Phase 8c bare-handle bounce that drove `SessionPrincipal.put/2` invariant

### 候选方案

- **A — Tactical fix in AgentNewLive**: add a `Workspace.invoke_template(workspace_uri, tmpl_name)` step after `add_template`. One additional dispatch call. Trade-off: keeps the "spawn Kind + register template + instantiate template" 3-step split; only the LV code path knows to chain them. Other create-paths (CLI, API) need the same chain.
- **B — Restructure agent lifecycle as explicit phases**: UI displays `registered → instantiated → running` with explicit transitions. "Not running" becomes "Registered but not instantiated". Trade-off: more UI complexity but no hidden gap; user sees what state they're in.
- **C — Collapse "create + instantiate" into a single dispatch action** (recommended for V2): unify the workflow at the Behavior layer. `Ezagent.Behavior.AgentLifecycle.create_and_start` is one cap-gated dispatch; AgentNewLive / CLI / API all invoke the same action. Trade-off: requires a new Behavior; cleanest abstraction; matches Phase 9 "dispatch is the only path" invariant (Decision #3, invariant 1).

### 链接

- Bug-fix candidate (if Allen wants it before V2): `apps/ezagent_plugin_liveview/lib/ezagent_plugin_liveview/agent_new_live.ex` line ~handle_event("create_agent"), insert call to `Ezagent.Workspace.Loader.invoke_template(workspace_uri, tmpl_name)` (or equivalent) after `add_template`
- Related test gap: there's no test that asserts "after AgentNewLive create_agent, the agent is actually receiving messages" — invariant_completion_requires_test pattern not applied to this flow



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
