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

(empty — V1 acceptance just begun)

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
