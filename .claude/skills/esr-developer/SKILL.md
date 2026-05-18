---
name: esr-developer
description: >-
  Use whenever working on the esr-ng codebase — touching any .ex file under
  apps/, modifying ARCHITECTURE.md/GLOSSARY.md/IMPLEMENTATION_ROADMAP.md,
  reviewing PRs, or answering questions about ESR (Elixir Smart Routing)
  patterns. ESR is a multi-agent platform with a strict dispatch model,
  capability-based access control (CapBAC), Behavior+Kind+URI primitives, and
  ~10 cross-PR architectural invariants captured in CI gates. This skill loads
  the invariants the dev team must respect, the anti-patterns to refuse, the
  how-to recipes for common contributor tasks, and pointer index to forensic
  notes. It is the "Allen replacement" for architectural judgment after
  Allen handed off at ESR v1 release (Phase 7 closeout, 2026-05-18). Trigger
  on any ESR contribution — even small ones — because the invariants are
  silent landmines (Decision #132 list/map in meta = silent drop, etc.).
---

# esr-developer

You are working in the **esr-ng** repo (Elixir Smart Routing). The architectural rules below were locked across 7 phases of brainstorm with Allen. Allen has handed off — your job is to keep the system honest without breaking the invariants he encoded as CI gates + Decision Log entries.

Read the relevant sections before writing code. **The most expensive bugs in this codebase are invariant violations that pass type-check + tests-pass and only surface as silent drops in production.**

## How to use this skill

For every task:

1. Read **Architecture invariants** below — what must stay true regardless of feature work.
2. Check **Anti-patterns the skill refuses** — if the task description matches one, push back BEFORE writing code.
3. Use **How-to recipes** for common contributor tasks (add plugin, Kind, Behavior, Template Class, routing rule, invariant test).
4. When debugging, jump to **Debug recipes** — symptom-first.
5. Cross-reference **Pointer index** for the durable record (Decision Log, forensic notes, SPEC).

For larger changes, also load `phase-specs/phase7/SPEC.md` and `phase-specs/phase7/VERIFICATION.md` directly — they have the V1-V5 acceptance criteria the system was built against.

---

## Architecture invariants (NON-NEGOTIABLE — CI gates each one)

### 1. **Dispatch is the only path** (Decision #3, #43, #127)

Every actor-to-actor message goes through `Esr.Invocation.dispatch/1`. **Never** `PubSub.broadcast` from one Kind to another, write directly to an external system from inside a `handle_info`, or call another Kind's GenServer.call directly. If you think you need to, you're describing a new **Receiver Kind** — model the external destination as `<scheme>://<external_id>` and implement `Esr.Behavior.Chat`'s `:receive` action (Decision #127).

CI gate: any module that `import`s `Phoenix.PubSub` AND writes to an external API without going through dispatch fails `receiver_kind_pattern_test.exs`.

### 2. **Capabilities are module references, not atoms** (Decision #137, plus the AtomShorthand trap)

`Esr.Capability.behavior` field is a `module()` (e.g. `Esr.Behavior.Chat`), NOT an atom shorthand (`:chat`). Atom mismatch silently denies because `Capability.matches?/2` requires exact equality on `behavior`. The parser converts string "chat" → `Esr.Behavior.Chat` at parse time; programmatic cap construction MUST use the module reference.

If your code path can't import the module reference (circular dep), use `:any` and scope by `:kind` instead — but document this as a trade-off, NOT an idiom (see forensic note `docs/notes/phase-7-handoff.md` §"Three trade-offs not to cargo-cult").

### 3. **Channel `meta` is `Record<string, string>`** (Decision #132)

For `notifications/claude/channel` payloads (per Anthropic channels-reference spec), every meta value MUST be a string. List/map/nested-object values cause claude TUI to silently drop the entire notification — no error to either side. Structured data goes in `content` as text breadcrumbs, or via a `tools/call` round-trip. The optional `meta.file_path` string (mirroring cc-openclaw convention) is the only way to surface a single file path through meta.

CI gate: `apps/esr_domain_chat/test/esr/behavior/chat_test.exs` "to_claude payload meta values are all strings".

### 4. **Workspace scoping is enforced via Esr.WorkspaceRegistry** (Decision #135)

`Esr.Behavior.Chat.invoke(:send, ...)` at `chat.ex:116` calls `Esr.Routing.Resolver.resolve/4` with `workspace_uri:` opt derived from `Esr.WorkspaceRegistry.lookup(session_uri)`. Without this plumbing, workspace-scoped routing rules silently never fire. New plugin Template Classes that spawn sessions MUST call `Esr.WorkspaceRegistry.bind(session_uri, workspace_uri)` after `SpawnRegistry.spawn`.

CI gate: `apps/esr_domain_chat/test/integration/workspace_isolation_test.exs`.

### 5. **Scope-bounded delegation cap shapes narrow, never broaden** (Decision #137)

`{:within_session, session_uri}` and `{:spawned_by, principal_uri}` on `cap.instance` are first-class shapes for orchestrator-style bounded delegation. They are MORE specific than a URI cap, not less. A cap holder with `{:within_session, A}` can only act within session A, never extending to session B. `:any` remains the only true wildcard.

CI gate: `apps/esr_core/test/esr/capability_test.exs` "scope-bounded instance tuples" describe block.

### 6. **User Kind structural baseline cap** (Decision #133)

Every user created via `Esr.Domain.Identity.Users.create/3` inherits `Esr.Entity.User.default_caps()` (currently `kind=:session, behavior=:any, instance=:any`). This is a STRUCTURAL invariant — without it, users can't send chat messages even from LV. The `:any` here is a circular-dep workaround (see invariant 2), NOT an idiom to copy into new plugin defaults.

CI gate: `apps/esr_domain_identity/test/esr/entity/user_test.exs` `describe "default_caps/0 (PR 27)"`.

### 7. **Dispatch mode is a transport choice, NOT a hard contract** (Decision #134)

`Behavior.@interface[:action] = :cast | :call | ...` declares the DEFAULT transport behavior. Callers (transports) can override (e.g. Feishu `InboundDispatcher` dispatches `Chat.send` as `:call` for error feedback). This is legitimate. Silent-drop on cap denial is the bug we avoid by using `:call` for inbound user surfaces.

When adding a new transport (Slack, Discord, email), the inbound path should use `:call` mode + decompose result + send error message back through the originating channel on `:unauthorized`.

### 8. **Plugin authoring contract** (Decision #88, Phase 6 Restructure)

Plugins register at `Application.start/2` via:
- `Esr.BehaviorRegistry.register(kind_module, action, behavior_module)`
- `Esr.SpawnRegistry.register(scheme, spawn_fn)` (URI-only, single-arg per Decision #65)
- `Esr.TemplateRegistry.register(class_module)` (single arg; reads `template_name/0`)
- `Esr.RoutingRegistry.declare_table(name, opts)`

`Mix.env()` in `Application.start/2` returns BUILD-time env (NOT runtime) when hot-installed via `mix esr.plugin.install`. Use `System.get_env("MIX_ENV")` if env-dependent boot logic is needed.

### 9. **No silent drops at user-facing surfaces** (Decision #134)

When an inbound message from a human-facing transport (Feishu, future Slack/Discord/email) fails dispatch (`:unauthorized` or otherwise), the transport MUST surface the error back to the human via the original channel + a reaction emoji. Silent drop is the bug `feedback_explicit_stop_signal_after_feishu` + Decision #134 were created to prevent.

### 10. **SessionTemplate fork = config only** (Decision #141)

SessionTemplate stores agent_slots + routing_rules + orchestrator_template_uri + workspace + parent_template_uri + version_hash. It does NOT store message history. Forking copies config only; instantiated sessions start with empty chat. Three-way merge of running sessions' working-copies is explicitly out of scope.

---

## Anti-patterns the skill refuses

If a contributor (or your own draft) attempts any of these, push back BEFORE writing code. Each refusal cites the violated Decision Log entry + the CI gate that will fail.

### Anti-pattern: "I'll PubSub.broadcast from this plugin to that one"

Refuse. Bypasses dispatch → bypasses CapBAC → bypasses audit → bypasses idempotency. Model the destination as a Receiver Kind (Decision #127). The pattern is `<scheme>://<id>` URI + `Esr.Behavior.Chat` `:receive` action + routing rule. Reference: `docs/notes/plugin-receiver-kind-contract.md`.

### Anti-pattern: "I'll bypass the cap check with admin_caps()"

Refuse. `admin_caps()` is the bootstrap principal's structural cap, NOT a goto for "make this work right now." If your code needs to act on behalf of a system component, use a scope-bounded delegation cap (`{:within_session, _}` or `{:spawned_by, _}` per Decision #137) — narrow, named, auditable.

### Anti-pattern: "I'll write the behavior as :chat in the cap struct"

Refuse. `Capability.behavior` is a module reference; the atom `:chat` is structurally different from `Esr.Behavior.Chat` and `matches?/2` will return false. Use the module reference. If a circular dep prevents that, use `:any` + narrow `:kind` (invariant 2 / forensic note).

### Anti-pattern: "I'll put structured data into channel notification meta"

Refuse. Decision #132: `meta` is `Record<string, string>`. Use `content` for structured data (as text), or `tools/call` round-trip if claude needs to read a file. The only structured-ish field allowed in meta is the single optional `file_path` string.

### Anti-pattern: "Inbound transport handler uses :cast for this dispatch"

Refuse for user-facing inbound transports (Feishu, future Slack/Discord/email). Decision #134 + `feedback_explicit_stop_signal_after_feishu`: human surfaces need synchronous error feedback. Use `:call` mode + decompose result + send error back through the channel + reaction emoji on denial.

### Anti-pattern: "Let's abstract a generic 'channel' covering both text + media"

Refuse. Phase 8 design call (per ROADMAP §9c + brainstorm trade-off): text/file = request-response (fits dispatch); streaming media = continuous flow (doesn't fit Behavior model). Generic abstraction hides the difference and invites misuse. Separate interfaces: ESR is control plane (signaling, auth, session, audit), media bytes go to external SFU (Dyte / LiveKit / Volcengine).

### Anti-pattern: "Make orchestrator deterministic — write the logic in Elixir"

Refuse. Decision D7-1 (#136): orchestrator is LLM-driven for team-composition reasoning. Permission control (the supposed benefit of deterministic dispatch) is preserved by scope-bounded cap delegation (Decision #137), not by removing reasoning.

### Anti-pattern: "SessionTemplate should fork with message history"

Refuse. Decision #141 (D7-7): fork unit = configuration only. Including message history would require three-way merge mechanics that are explicitly deferred to dev-team-v1.x+.

### Anti-pattern: "Add `mix esr.plugin.uninstall`"

Refuse for now. Decision #142 (D7-8): plugin unload requires Kind lifecycle management for live instances of the unregistered Kind — non-trivial. Defer until dev team agrees they need it, then design carefully (not as a symmetric mirror of `install`).

---

## How-to recipes

### How-to: add a new plugin

1. Create OTP app under `apps/esr_plugin_<name>/` with standard Mix layout.
2. Add `:esr_core` as in_umbrella dep in mix.exs.
3. Implement `EsrPlugin<Name>.Application` with `start/2`:
   - Register Behaviors: `Esr.BehaviorRegistry.register(kind, action, behavior_module)`
   - Register spawn fns: `Esr.SpawnRegistry.register(scheme, fn uri -> ... end)` (URI-only single arg)
   - Register Template Classes (if any): `Esr.TemplateRegistry.register(class_module)`
   - Declare routing tables: `Esr.RoutingRegistry.declare_table(name, opts)`
4. If the plugin spawns sessions, call `Esr.WorkspaceRegistry.bind(session_uri, workspace_uri)` after `SpawnRegistry.spawn` to plumb workspace scope (invariant 4).
5. Test via `mix esr.plugin.install /path/to/plugin` against running ESR (invariant 8).

Pre-built example: `apps/esr_plugin_echo/` (smallest reference plugin).

### How-to: add a Kind

1. Create `apps/<your_domain>/lib/<your>/entity/<your_kind>.ex`.
2. Implement `@behaviour Esr.Kind` with three callbacks:
   - `type_name/0 → :your_kind` (snake atom; appears in cap `kind` field)
   - `behaviors/0 → [Esr.Behavior.X, ...]` (what `init_slice` runs at boot; per-Kind `BehaviorRegistry.register` decides what actions dispatch)
   - `persistence/0 → :ephemeral | :on_terminate | {:snapshot, :on_change}`
3. Register a spawn fn for the URI scheme in your plugin's Application.start/2.
4. If your Kind carries an Identity slice for caps, document the `init_slice/1` args shape (typically `%{initial_caps: MapSet.t()}`).

Reference: `apps/esr_domain_chat/lib/esr/entity/agent_template.ex` (newest, simplest Phase 7 example).

### How-to: add a Behavior

1. Create `apps/<your_domain>/lib/<your>/behavior/<your_behavior>.ex`.
2. `@behaviour Esr.Behavior`.
3. Implement `state_slice/0`, `init_slice/1`, `interface/0` (action schema), `invoke/4`.
4. Register per-Kind in the plugin's `register_<X>_behaviors()`:
   `:ok = BehaviorRegistry.register(SomeKind, :action, YourBehavior)`.

Reference: `apps/esr_domain_chat/lib/esr/behavior/chat.ex` (most complex, well-commented).

### How-to: add a Template Class

1. Module implementing `@behaviour Esr.Kind.Template` with callbacks:
   - `template_name/0 → "your.class.name"` (stable string id)
   - `validate/1 → :ok | {:error, _}` (pre-persist schema check; optional, default `:ok`)
   - `instantiate/3` → effectful spawn of one or more Kinds; **must be idempotent** (re-call on already-spawned returns same URIs)
2. Register at plugin boot: `:ok = Esr.TemplateRegistry.register(YourTemplateClass)`.
3. If your Template Class spawns sessions, call `Esr.WorkspaceRegistry.bind/2` for each spawned session URI (invariant 4) — `Esr.Workspace.Loader.invoke_template` does this for the canonical session classes; custom Template Classes follow the same pattern.

Reference: `apps/esr_domain_chat/lib/esr/template/generic_session.ex`.

### How-to: add a routing rule

Two paths:

- **Programmatic (test / runtime)**: `Esr.Routing.RuleStore.add(table_name, matcher, receivers, granted_by, opts)` then `RuleStore.load_into_registry(table_name)`.
- **LV / CLI (admin)**: `/admin/routing` form, or `mix esr.routing.add_rule`.

Always pass `workspace_uri:` opt unless the rule is intentionally global (matches messages from any workspace).

### How-to: write an invariant test

Pattern (see `apps/esr_domain_chat/test/integration/workspace_isolation_test.exs` for the canonical example):

1. **`use EsrCore.DataCase, async: false`** (the test exercises persistence + dispatch + sandbox semantics)
2. Spawn the production setup (`Esr.SpawnRegistry.spawn(uri)`, `WorkspaceRegistry.bind`, `RuleStore.add` etc.) — not mock objects
3. Drive the production code path (`Esr.Invocation.dispatch`) — not direct function calls
4. Assert via observable side-effects (audit log `invocations` table, `messages` table, message_routings table) — not internal slice state
5. Name the test file `<invariant>_test.exs` so it's discoverable; tag `:slow` if it spawns OS subprocesses

The invariant test is what stops a future PR from re-breaking the architectural rule. Phrase the failure message so a future debugger immediately understands what was violated.

### How-to: install a new plugin into running ESR (no phx restart)

`mix esr.plugin.install /path/to/your_plugin_otp_app`

Caveats:
- `Mix.env()` returns BUILD-time env (use `System.get_env("MIX_ENV")` if env-sensitive)
- Plugin unload is NOT supported (Decision #142). To remove a plugin, restart phx after deleting its OTP app from the umbrella.

---

## Debug recipes (symptom-first)

### Symptom: message disappeared / silent drop

In order of likelihood:

1. **Channel notification meta has non-string value** (Decision #132). Grep `meta = ...` in your push path; ensure every value is `String.t()`. Run `apps/esr_domain_chat/test/esr/behavior/chat_test.exs` "to_claude payload meta values are all strings".
2. **Cap shape mismatch on `behavior`** (invariant 2). Check via `:rpc` that `Capability.matches?/2` returns true for the user's cap + the action's needed cap. Common error: cap struct has `behavior: :chat` (atom) while needed has `behavior: Esr.Behavior.Chat` (module).
3. **Workspace scope not plumbed** (invariant 4). Check `WorkspaceRegistry.lookup(session_uri)` returns `{:ok, _}` for the session involved. If `:error`, the session was spawned without `bind` (custom Template Class missed step 5 of how-to add a plugin).
4. **Inbound transport using `:cast`** (Decision #134). For Feishu/Slack/etc inbound, verify the dispatch uses `mode: :call` and decomposes the result.

### Symptom: `:unauthorized` despite cap granted

1. Check the user's User Kind is **alive** (in-memory state). `Esr.Identity.list_caps_for/1` returns `MapSet.new()` if the Kind isn't spawned. Spawn via `Esr.SpawnRegistry.spawn(user_uri)` if needed.
2. Verify cap struct shape (invariant 2 — module vs atom on `behavior`).
3. For scope-tuple caps, verify the scope dimension matches the needed action's context — e.g. `{:within_session, A}` won't match an action targeted at session B (Decision #137).
4. For `{:spawned_by, _}` caps: until PR 40 ships the lineage registry, this shape returns false (deny-by-default placeholder, Decision #137 forensic note).

### Symptom: orphan node sidecar after phx restart

The sidecar's `process.stdin.on('end', ...)` handler may have been refactored away. Run `apps/esr_plugin_feishu/test/sidecar_orphan_reap_test.exs --include slow` — the integration test spawns + kills + asserts the OS pid dies within 3s. If it fails, restore the EOF handler in `apps/esr_plugin_feishu/priv/ws_sidecar/main.js`.

### Symptom: workspace-scoped routing rule never fires

Check that `WorkspaceRegistry.lookup(session_uri)` returns `{:ok, workspace_uri}` for the session the message originated in. If `:error`, the session is unbound — workspace_uri opt to Resolver will be `nil` → rule with `workspace_uri: <something>` won't match (Decision #135).

### Symptom: SessionTemplate fork lost lineage

Check `parent_template_uri` field on the new template. If `nil`, the fork code path didn't preserve it — `Esr.Entity.SessionTemplate.fork/2` MUST set `parent_template_uri = parent_uri@hash` (the specific source hash). CI gate: `template_fork_lineage_test.exs`.

---

## Project conventions

- **`uv run` not `python` / `python3`** — global hook blocks raw python invocations; always prefix with `uv run`.
- **`pnpm` not `npm`** — same project convention.
- **`agent-browser` for any UI/web debugging** — never iterate via "try it and tell me what you see"; launch headless Chrome from the agent side and screenshot. Memory `feedback_agent_browser_debug`.
- **Bilingual docs convention**: `docs/<name>.md` (English) + `docs/<name>.zh_cn.md` (Chinese) parallel files; send the `.zh_cn.md` via Feishu; sync edits both ways. Memory `feedback_bilingual_docs_convention`.
- **Decision Log new entry**: append to ARCHITECTURE.md Appendix B with next sequential number; format follows existing entries (subject line in bold + WHY + DRIFT DEFENSES). Phase 7 added #135-#144.
- **Forensic notes go in `docs/notes/`** — not inline in code comments. Cross-link from Decision Log entry + (where relevant) from a moduledoc.
- **Remote browser URLs use 100.64.0.27 (Tailscale IP), not localhost** — Allen accesses remotely. Memory `feedback_remote_browser_ip`.

---

## Pointer index

The durable record. When you (or a future contributor) need authoritative answers:

| Source | What's there |
|---|---|
| `ARCHITECTURE.md` Decision Log Appendix B | #1-#144, full architectural history (Phase 7 ended at #144) |
| `ARCHITECTURE.md` §17.6 | Cap delegation baseline → v1 evolution (Decision #137) |
| `ARCHITECTURE.md` §7 | CapBAC model, cap-for-action, default capability table |
| `ARCHITECTURE.md` §12.8 | CC Channel adapter design (meta schema invariant inline) |
| `GLOSSARY.md` | All 16 Phase 7 terms + 100+ prior project terms;易混淆词消歧 in §3 |
| `IMPLEMENTATION_ROADMAP.md` §9 | Phase 6 closeout delivery accounting |
| `IMPLEMENTATION_ROADMAP.md` §9b | Phase 7 delivery accounting (this is where v1 release is recorded) |
| `IMPLEMENTATION_ROADMAP.md` §9c | Phase 8 record-only (multimedia / streaming / Dyte) |
| `phase-specs/phase7/SPEC.md` | Phase 7 design (LOCKED v3) |
| `phase-specs/phase7/VERIFICATION.md` | V1-V5 acceptance criteria + e2e flows |
| `phase-specs/phase7/PLAN.md` | 24-PR sequence + per-PR workflow + risk register |
| `phase-specs/phase7/DECISIONS.md` | Implementation-time IMPL-7-N decisions |
| `docs/notes/phase-7-handoff.md` | ESR v1 release note + 3 trade-offs not to cargo-cult |
| `docs/notes/phase-6-architecture-closeout.md` | Phase 6 forensic record (meta schema fix + User default caps + InboundDispatcher mode) |
| `docs/notes/plugin-receiver-kind-contract.md` | Why Plugin X cannot PubSub.broadcast to Plugin Y (Decision #127) |
| `docs/notes/phase-7-resume-state.md` | Per-PR live status table (resume any session mid-Phase-7) |

---

## When this skill conflicts with what's in front of you

Code wins. If you find a discrepancy between this skill's description of an invariant and what the code actually does, **the code is authoritative**. Either:
- The invariant changed and the skill wasn't updated (open a PR updating the skill)
- The code drifted from the invariant (open a PR fixing the code; the skill describes intent)

Don't silently change either to match. Surface the discrepancy in the PR description so a reviewer (or future Claude with context) can adjudicate.
