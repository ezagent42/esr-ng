# Phase 7 — Implementation-time DECISIONS

**Status:** INITIALIZED 2026-05-18 (empty; will accrete during PR sequence).
**Purpose:** Capture judgment calls made DURING implementation that weren't in the SPEC. SPEC contains the LOCKED design; DECISIONS records the in-the-trenches "I chose X over Y because Z" that come up when actually writing code.

When a SPEC ambiguity is hit:
1. Try to resolve in-PR without escalating (most cases)
2. Write a DECISIONS row capturing the choice + reasoning
3. If the choice is architecturally significant (changes a Phase 7 invariant or contradicts the SPEC), block on Allen and document the dialogue

When a SPEC contradiction is hit:
1. Stop. Don't pick one arbitrarily.
2. Feishu Allen with the contradiction + recommendation.
3. Document the resolution here once decided.

Decisions promote to ARCHITECTURE.md Decision Log at Phase 7 closeout (7-4 PR 53) if they have lasting architectural significance.

---

## Decision template

```markdown
### IMPL-7-N: Brief title (PR # / date)

**Context:** What was happening in the code that forced a choice.
**Options considered:**
  - A: ...
  - B: ...
**Choice:** A (or B, or hybrid).
**Reasoning:** Why this one. Cite SPEC sections if relevant.
**Promote to Decision Log?** Yes/No, with justification.
```

---

## Decisions

*(none yet — population begins with PR 31)*
