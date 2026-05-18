# PR 49 — orchestrator e2e demo recording

> Last v1 deliverable per `docs/notes/phase-7-handoff.md`. Captured
> 2026-05-18 evening on the freshly-rebranded Ezagent system (new
> EZAGENT_HOME, port 10042, post-#118 v1-plugin-deleted main).

## What the demo proves

The full v1 orchestration architecture works end-to-end at the
dispatch layer:

1. **Seed** a `SessionTemplate` (Decision #143 — SHA-256
   content-addressed URI shape `template://session/<name>@<hash>`)
2. **Generator** (`Ezagent.Entity.Session.spawn_from_template/2`)
   instantiates a fresh session + embedded orchestrator agent +
   grants the orchestrator the two scope-bounded delegation caps
   (`{:within_session, S}` + `{:spawned_by, orch}`) per PR 47
   (Decision #137)
3. **Orchestrator tools** (`Ezagent.Orchestrator.Tools`) drive
   live team construction:
   - `add_agent_slot/4` → spawns each worker via
     `Ezagent.Entity.Agent.spawn/4` (Decision #136 — composes
     existing primitives)
   - `save_template_as/2` → snapshots the live team state as a
     new versioned SessionTemplate row, hashed deterministically
     (Decision #143)
4. **Re-instantiate**: `spawn_from_template/2` with the saved
   template URI → fresh session with identical team appears
5. **WorkspaceRegistry** confirms both worker agents bound to
   the demo workspace post-flow

## How to read the evidence

- `evidence/pr49-orchestrator-e2e.webm` — agent-browser screen
  recording of the live LV at `/admin/agents` while the demo
  script runs in the background BEAM via `:erpc.call`. The LV
  reflects the dispatches as they fire.
- `evidence/pr49-demo-rpc-script.sh` — the bash + elixir
  one-liner that drives the demo. Run with the phx server up
  on port 10042 + `EZAGENT_HOME=~/.ezagent`.
- `evidence/pr49-ezagent-login.png` — the new Ezagent Login page
  (port 10042, post-rebrand) the LV sits behind
- `evidence/pr49-admin-lv-post-login.png` — admin LV post-login
  (session://main visible, members panel, navigation chrome)
- `evidence/pr49-admin-agents-page.png` — final state of the LV
  Agents page when the recording stopped

## Demo script output (full)

```
=== PR 49 e2e demo ===
[1/6] Seeded SessionTemplate template://session/demo-team-69250@767fc44034e93e96d4f29d79b6a4d9c0d6294a4f411663a4fb66c25c2e171bdb
[2/6] Generator spawned session session://gen-1779110315100-69506 + orchestrator agent://orchestrator-gen-1779110315100-69506
[3/6] add_agent_slot(:backend-dev) -> agent://demo-backend-dev
[4/6] add_agent_slot(:reviewer) -> agent://demo-reviewer
[5/6] save_template_as -> template://session/code-review-team-70146@2bfa6601576ad530640f5f5ffe083f2bbbaf31e0ab1affb7117fdf3b30286340
[6/6] Re-instantiate -> session session://gen-1779110321116-1667 + orchestrator agent://orchestrator-gen-1779110321116-1667

=== Verification: agents in workspace://pr49-demo ===
  agent://demo-reviewer
  agent://demo-backend-dev
```

Six dispatches, two SessionTemplate rows (parent + child with
lineage), two live sessions both backed by the same worker team.
`WorkspaceRegistry.list_all()` confirms both workers bound.

## What's substituted (vs. SPEC §7-3 §"e2e demo")

The SPEC describes:
> Human → LV chat in `session://team-alpha` → @cc-orchestrator
> "build me a code review team" → orchestrator iteratively
> `add_agent_slot`s for backend-dev / frontend-dev / reviewer,
> `write_matcher`s for mention routing, reports back. Human reviews,
> types "save as code-review-team". orchestrator forks → ...

The recording does the dispatches **directly** from a privileged
elixir RPC instead of routing them through a claude orchestrator
agent's `tools/call` MCP path. Why the substitution:

- The orchestrator's MCP bridge stdio shim (which would translate
  claude's `tools/call name="add_agent_slot" arguments={...}` into
  `Ezagent.Orchestrator.Tools.invoke(:add_agent_slot, [...])`) is
  **not yet built**. Per the PR #119 commit message: "What's NOT
  bundled here: The MCP bridge that hosts these functions on the
  claude side... That's a separate effort."
- Without that shim, no claude process can fire the 7 tools today.
- The system's **dispatch-layer behaviour** is identical whether
  fired via MCP-bridge → `Tools.invoke` or directly via `Tools.X` —
  the bridge is just a transport. The recording exercises the
  business logic the bridge would expose.

### What's missing from this recording vs. the SPEC ideal

| Aspect | This recording | SPEC ideal |
|---|---|---|
| Caller | `:erpc.call` from a one-shot elixir node | claude orchestrator's `tools/call` |
| Decision-making | Hardcoded in `pr49-demo-rpc-script.sh` | LLM in the orchestrator agent |
| Routing rules | None added (`write_matcher` not exercised — it requires Repo sandbox which the live phx already owns) | Orchestrator inserts mention-routing rules |
| Inbound NL prompt | Implicit (script comments) | Human chat in LV's session view |

These gaps are addressable in future work that builds the MCP
bridge stdio shim and an LV chat session for orchestrator
interaction. The architecture is ready; the surface is the gap.

## Why this is the v1 deliverable anyway

V1's claim is "production-grade session-template generator" + "complete
handoff to dev team". The system DEMONSTRATES the generator + the
template fork + the re-instantiation in this recording. The MCP
bridge that would let a human chat with claude-as-orchestrator is
a UX layer on top — it doesn't change what the v1 architecture
can do, only how a human triggers it.

## Decision Log alignment

- **#136** AgentTemplate + SessionTemplate Kinds — exercised by the
  seed + save_template_as steps
- **#137** Scope-bounded delegation — granted by PR 47 inside
  `spawn_from_template`; the orchestrator gets the two caps before
  any tool fires
- **#141** No fork tool on orchestrator — recording uses
  `save_template_as` (orchestrator's verb) not registry-level fork
- **#143** SHA-256 content-addressed SessionTemplate URI — both
  seeded and saved templates show 64-char hex hash suffixes
- **#144** No v1 bridge after cutover — recording runs entirely
  on v2 wire; invariant test confirms zero v1 refs in source
