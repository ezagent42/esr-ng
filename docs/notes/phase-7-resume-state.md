# Phase 7 resume state (for next Claude Code session)

**Updated:** 2026-05-18 (end of brainstorm + SPEC + PR 31 session).
**Status:** Phase 7 in flight. SPEC v3 LOCKED + VERIFICATION + PLAN + DECISIONS shipped. PR 31 merged. PRs 32-54 pending.

If a fresh Claude Code session is picking up Phase 7 implementation, read this first. Then read in order:

1. `phase-specs/phase7/SPEC.md` — full design (LOCKED v3)
2. `phase-specs/phase7/VERIFICATION.md` — V1-V5 acceptance criteria
3. `phase-specs/phase7/PLAN.md` — 24-PR sequence + per-PR workflow + risk register
4. `phase-specs/phase7/DECISIONS.md` — implementation-time judgment calls
5. `ARCHITECTURE.md` Decision Log entries #132-#134 (Phase 6 closeout) — these are the most recent architecture decisions before Phase 7

## Where Phase 7 stands right now

| Sub-step | PR | Status | Notes |
|---|---|---|---|
| Pre-7 docs | 30/#84 | ✅ merged | SPEC + VERIFICATION + PLAN + DECISIONS |
| 7-1-a workspace enforcement | 31/#85 | ✅ merged | New Esr.WorkspaceRegistry (5th ETS Registry); chat.ex:116 plumbs workspace_uri |
| 7-1-b CC v1→v2 cutover | 32 | ⏳ pending | LARGE. Blast radius listed in SPEC §7-1; delete entire esr_plugin_cc_bridge_v1_prototype app + migrate all references in cc_pty, ezagent, chat.ex, agent.ex, controllers, 3 test files |
| 7-1-c `mix esr.bootstrap` | 33 | ⏳ pending | New mix task wrapping esr.home.init + esr.home.adopt_db + ecto.migrate + health check |
| 7-1-d CLI token auth | 34 | ⏳ pending | Per-user bearer token + LV mint UI + parity invariant test `cli_lv_cap_parity_test.exs` |
| 7-1-e ws sidecar EOF reap | 35 | ⏳ pending | Add `process.stdin.on('end', () => process.exit())` to `apps/esr_plugin_feishu/priv/ws_sidecar/main.js` + integration test |
| 7-1-f `mix esr.plugin.install` | 36 | ⏳ pending | Runtime hot-load via :application.load/:application.start; concurrency lock; Mix.env() pitfall doc |
| 7-2 templates (5 PRs) | 37-41 | ⏳ pending | AgentTemplate + SessionTemplate Kinds; template caps; Agent.spawn/4; Generator |
| 7-3 orchestrator (8 PRs) | 42-49 | ⏳ pending | Capability.matches?/2 extension; ctx :session_uri; cc-orchestrator template; 7 MCP tools; persistence flip; fork/merge; e2e demo |
| 7-4 handoff (5 PRs) | 50-54 | ⏳ pending | ESR skill; 4 docs; ≥8 invariant tests; Decision Log #135-#144; forensic note + v1 release |

## Operational facts about the environment

- Live phx.server runs from `/Users/h2oslabs/Workspace/esr-ng/.claude/worktrees/phase-2/`. Restart with `kill <pid>` + `nohup env ELIXIR_ERL_OPTIONS="-name esr_runtime@127.0.0.1 -setcookie $(cat ~/.esr-ng/default/runtime/cookie)" mix phx.server > /tmp/esrserver.log 2>&1 &`
- DB at `~/.esr-ng/default/db/esr_core.db` (already migrated out of repo per Phase 6 PR 1)
- Worktree branch is `phase-7/*`; merge to `main` directly via `gh pr merge --admin --squash --delete-branch`
- Allen's chat_id for Feishu reports: `oc_d9b47511b085e9d5b66c4595b3ef9bb9`
- Live `cc-demo` agent in `session://main` is Allen's test target — don't break it during PR 32 v1→v2 cutover without a known-good rollback
- Other worktrees on the repo: yao.shengyue runs an independent ESR at `/Users/yao.shengyue/Workspace/esr-realm-yao/` — never kill her processes (`yao.shengyue` user) or modify her dir

## Allen-authorized actions for this work

- Create / push / admin-merge PRs (per `feedback_admin_merge_authorized` + AFK execution authorization 2026-05-18 09:17)
- Modify ARCHITECTURE / GLOSSARY / IMPLEMENTATION_ROADMAP (per Phase 6 closeout pattern)
- Delete `esr_plugin_cc_bridge_v1_prototype/` directory in PR 32
- Restart phx.server locally for verification
- NOT authorized: force-push to main, skip git hooks, push to yao.shengyue's repo

## Workflow per PR (from PLAN.md)

For each pending PR:

1. Read SPEC + VERIFICATION rows the PR closes
2. Branch off origin/main (rebase if main moved)
3. Subagent-review (Explore agent, opus model): "What existing code does this touch? Hidden coupling? Architectural assumptions to respect?"
4. Implement per SPEC row's "Detail" field
5. Write tests gating the row's "Acceptance" field
6. `mix compile` + `mix test <affected app subset>`
7. Self-run SPEC_REVIEW 8-item checklist; document in PR body
8. Subagent re-review against new code
9. `git commit + push + gh pr create + gh pr merge --admin --squash --delete-branch`
10. Update PLAN.md row to ✅
11. If decision point hit (architecture surprise / SPEC ambiguity): Feishu Allen with question; block on response unless trivial
12. Append IMPL-7-N decision to DECISIONS.md as needed

## Known traps from this session

- **`gh pr merge --admin` requires rebase if main moved since branch creation.** Pattern: `git fetch origin main && git rebase origin/main && git push --force-with-lease && gh pr merge --admin --squash --delete-branch`
- **`git checkout main` fails inside the phase-2 worktree** because main is checked out in another worktree (root). Use `git fetch origin main` + branching off `origin/main` if needed.
- **Tests that touch `Esr.Audit.Writer` flushes can pollute the test sandbox.** PR 31's workspace_isolation_test.exs uses `Process.sleep(250)` instead of forcing flush — that works.
- **`Capability.matches?/2` only handles `:any` or exact equality on the `instance` field today.** Phase 7 PR 42 extends it for tuple shapes. Don't pre-emptively use tuple-shaped caps before PR 42.
- **CC channel v1→v2 blast radius is bigger than my SPEC v1 thought.** Production code in chat.ex (lines 29, 197, 199), agent.ex (moduledoc line 10), web controller (lines 9, 34), plus 3 test files. SPEC v3 lists them all.

## Brainstorm history (so the next session has context for any pushback Allen makes)

| Round | Key reframes |
|---|---|
| 1 (morning) | Orchestrator A (LLM) vs B (deterministic) → A; monolithic Phase 7 with 4 sub-steps; handoff = complete (Allen leaves); Federation dropped; DB migration mandatory; new ESR developer skill |
| 2 (afternoon) | Orchestrator = session-internal manager (NOT ephemeral authoring tool); Generator = spawn program; SessionTemplate is the production unit, forkable; AgentTemplate keeps name (no Blueprint rename — Template umbrella already exists in `Esr.Kind.Template` in core); AgentTemplate minimal (settings dir + cwd pointer); ESR install = `mix esr.bootstrap` only; plugin hot-install yes, hot-unload deferred |
| 3 | "orchestrator fork" was misnomer — fork is SessionTemplate registry operation; 3 session-creation entry points; D7-10 git-style SHA hash versioning + mutable tag overlay; AgentTemplate adds `CLAUDE_CONFIG_DIR` env var pattern + macOS Keychain caveat |
| (VERIFICATION reframe) | Allen wanted V1-V5 acceptance criteria FIRST, then SPEC walked through as serving each V — caught one borderline (CLI fork command redundant with orchestrator's update_template) |

## Memory keywords for the next session

(These should auto-load via the memory system: search for "phase 7", "orchestrator", "SessionTemplate", "AgentTemplate", "WorkspaceRegistry", "scope-bounded delegation", "Capability.matches", "CLAUDE_CONFIG_DIR")
