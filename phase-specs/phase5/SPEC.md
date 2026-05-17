# Phase 5 — Feishu adapter + CC channel production + Pty-Web + PTY config UI

**Status:** **DRAFT** 2026-05-17 (Allen pending review). **Do not implement yet.**

**Source:** `IMPLEMENTATION_ROADMAP.md §8` + Allen's 2026-05-17 directives:
- "feishu adapter 应该和现在的 LV 进行结合，例如在一个 session 中有一个绑定 feishu chat id 的功能" → Feishu must integrate with LV via per-session chat_id binding, not be a standalone surface
- "当前我们可以启动 pty 来执行 shell 脚本，但 LV 上还没有可以配置的地方" → cc-pty Template exists but there's no operator-friendly LV config; JSON-paste is awkward
- Reference to memory `feedback_phase_planning_reads_main_docs`: this SPEC was drafted *after* reading `IMPLEMENTATION_ROADMAP.md §8` first

## North star

After Phase 5, an operator can:
1. Bind any LV `session://X` to a Feishu group chat → messages flow both ways automatically; LV is the same "system control panel" feeling whether the user is on web or in Feishu
2. Configure a new cc-pty agent via a friendly LV form (no JSON paste required); see PTY status live
3. View a CC session's TUI directly in the browser (Pty-Web — xterm.js in LV)
4. CC channel production-grade: the Phase 1 `v1_prototype` bash bridge is gone; CC channel is a proper plugin with per-instance auth + capability scoping

---

## Scope (4 sub-phases)

### 5a · Feishu adapter integrated with LV (Allen's binding requirement)

**Theme:** Session ↔ Feishu chat_id is a first-class binding stored on the Session Kind; messages routed by ESR end up in Feishu via webhook; Feishu group `@`-mentions route back into ESR via webhook receiver.

**UX changes:**

- `/admin` (current AdminLive): each session in the left sidebar gets a small badge if bound to a Feishu chat — e.g. `session://main 🔗 oc_xxxx` (or "(not bound)" link)
- Per-session header: "Bind to Feishu chat" button → modal asking for `chat_id`; on save → call new `Esr.Behavior.Session.bind_feishu_chat/2` (CapBAC-gated, requires `session.feishu_bind` cap)
- Once bound: every message sent through LV's chat compose → also dispatched to `feishu://<chat_id>/behavior/feishu_outbound/send` (the new Feishu adapter Kind handles webhook out)
- Inbound: Feishu webhook hits `POST /api/feishu/webhook` → constructs `%Esr.Message{sender: user://<feishu_user>, ...}` → dispatches into the bound session via the receiver-table → appears in LV in real time
- New `/admin/feishu` LV: list bound sessions + Feishu app status + recent webhook events
- "Floating agents" sidebar gets a new entry `feishu://*` agents (visible Feishu identities mapped to ESR users)

**Decision points (defaults; will set unless Allen objects):**

| # | Question | Default |
|---|---|---|
| 5a-D1 | Per-session binding stored where? | In Workspace.config (durable, survives restart) — `session_feishu_bindings: %{session_uri => chat_id}` |
| 5a-D2 | Many-to-many or 1-to-1? | 1 session ↔ 1 Feishu chat (simpler; if Allen needs 1↔N later, extend by upgrading to `[chat_id]` list) |
| 5a-D3 | Feishu user → ESR User mapping | Auto-create `user://feishu/<feishu_user_id>` on first inbound msg from unknown sender (with empty caps; admin grants later) |
| 5a-D4 | Outbound failure handling | Audit row + LV flash, do not retry (operator can resend); per memory `feedback_let_it_crash_no_workarounds` no silent fallback |
| 5a-D5 | Adapter language | Per Roadmap §5b: Elixir for ESR side + Python for Feishu bot (lark SDK), separate process, communicates via WS or HTTP |
| 5a-D6 | Reuse old esr Python code | Yes — `adapters/feishu/` + `handlers/feishu_app/`; lark SDK + signature check are the parts that take longest to get right |

**Invariant tests (per `feedback_completion_requires_invariant_test`):**
- Bind session X to chat_id Y → LV send → assert outbound webhook fires with chat_id Y
- Inbound webhook from chat_id Y with text "hello" → assert ESR session X receives `%Esr.Message{text: "hello"}` via Resolver (NOT bypassing)
- Routing isolation: bind session X to chat_id Y, bind session Z to chat_id Y → second bind rejected (1-to-1 invariant)

---

### 5b · CC channel production rewrite

**Theme:** Replace Phase 1 `esr_plugin_cc_bridge_v1_prototype` with `esr_plugin_cc_channel` proper (Roadmap §8 5b).

**UX changes:**

- `/admin` DebugPanel "CC Bridges (v1 prototype)" → renamed "CC Channels" (no v1 prototype label)
- Per-bridge row: shows CC channel handshake status + connect-token validity + caps granted (vs current: just connected/disconnected)
- New `/admin/cc-channels` LV: list registered CC instances (workspace-scoped) + revoke connect token + force-disconnect

**Migration plan (two-track for safety):**
1. New `esr_plugin_cc_channel` lives alongside `esr_plugin_cc_bridge_v1_prototype`; both run in parallel
2. Old `cc-bridge-attach.sh` keeps working for existing operators
3. New CC instances get a new `cc-channel-attach.sh` (or env flag)
4. Once all internal CC instances migrated → mark v1 prototype as deprecated; one-PR removal in 5d

**Open question:**
- Allen earlier (2026-05-15) mentioned CC channel error reporting via hook (we shipped PR #34 for that in `cc-events`). 5b should keep that endpoint, just have the new channel plugin emit hook-bypass events too

---

### 5c · Pty-Web (xterm.js in LV)

**Theme:** Browser-rendered TUI for any PTY-managed agent (cc-pty initially; Spec extensible to other PTY processes).

**UX changes:**

- `/admin/agents/:agent_uri/pty` LV: full xterm.js terminal renderer; PTY output streams via Phoenix.PubSub on `<agent_uri>:pty:output`; input from the browser sends a `Esr.Behavior.Pty.input` invocation back (NOT raw PubSub — invariant #1 hard rule)
- Workspace detail page: cc-pty templates row gets a "📺 Open terminal" link to the pty view
- Read-only mode for non-admins (can view but not type)

**Open question:**
- Per Roadmap §8, frontend framework decision: **xterm.js + LiveView hook** (default — matches existing LV stack) vs **separate React/Vite shell**. Recommend xterm.js + LV hook for v1 (no new framework, no new build pipeline).

---

### 5d · PTY config UI (Allen's new request)

**Theme:** Make cc-pty Template configurable from LV without JSON paste.

**Gap:** WorkspaceDetailLive's add-template form mode currently only handles `session.generic` Class. cc-pty requires JSON mode (`{"class":"cc.pty","agent_uri":"agent://X","cwd":"/path"}`), which is operator-hostile.

**UX changes:**

- WorkspaceDetailLive add-template form gets a Class dropdown: `[session.generic, cc.pty, other-via-JSON]`
- Selecting `cc.pty` → form auto-shows `agent_uri` + `cwd` fields (specific to cc.pty Class) — no JSON paste
- The form is **declarative-from-Class**: each registered Template Class declares its own form schema (`@form_fields`), AddTemplateForm renders dynamically from the registered Classes. This means future Template plugins (Phase 6+ shell-script-runner, scheduled-job Class, etc.) get a UI for free without touching WorkspaceDetailLive
- New `/admin/agents/:agent_uri` LV: shows live PTY status — running / crashed / exit code / restart count / last 50 lines of output (linked to 5c xterm view for live tail)
- "Restart PTY" button (cap-gated)

**Decision points:**

| # | Question | Default |
|---|---|---|
| 5d-D1 | Form schema declaration: per-Class behaviour callback or in registry? | `Esr.Kind.Template` callback `form_fields/0` (each Class self-describes) — keeps plugin authors in their own module |
| 5d-D2 | Field types | Start with `:text` + `:path` + `:uri` + `:select` (4 types cover cc.pty + session.generic); add as new Template Classes need them |
| 5d-D3 | "Other-via-JSON" fallback | Yes — keeps escape hatch for custom Classes the operator wrote |

---

## PR plan (~6 PRs, sequenced)

| PR | Sub-phase | Theme | Est. LOC |
|---|---|---|---|
| 1 | 5d | Template form schema (`form_fields/0` callback) + WorkspaceDetailLive dynamic form | ~250 |
| 2 | 5d | `/admin/agents/:agent_uri` LV (PTY status + restart) | ~300 |
| 3 | 5c | Pty-Web LV with xterm.js + input invocation path + cap-gate | ~400 |
| 4 | 5a | Session ↔ Feishu chat_id binding (Workspace.config field + Session behaviour action + LV badge/modal) | ~300 |
| 5 | 5a | Feishu adapter plugin (Elixir adapter + Python bot port from old esr) + webhook in/out | ~600 (mostly Python port) |
| 6 | 5b | New `esr_plugin_cc_channel` (parallel to v1_prototype) + LV "CC Channels" view | ~500 |

Total ~2,350 LOC. Each PR has an invariant test gate.

## Non-goals (deferred to Phase 6+)

- Federation (Decision #48 — still v0+1)
- Multi-Feishu-app routing (one app per ESR instance for now)
- Pty-Web shared cursor / collaborative editing
- Migration of last v1_prototype users (lives in 5b deprecation PR, not blocking)
- General shell-script-runner Class (separate from cc-pty; Phase 6 if Allen wants it)

## Per memory `feedback_flag_user_assist_steps`

User-assist steps required during Phase 5:
- 5a-D6: Allen needs to provision Feishu app credentials + webhook URL (operator action, not automatable)
- 5a-D3: Initial admin-grant for auto-created `user://feishu/*` users (LV action)
- 5b: Allen runs a real CC instance against new channel plugin for production validation
- 5c: Allen opens a workspace browser tab + verifies PTY output renders correctly (the e2e usability bar — agent-browser can screenshot but only Allen can call "looks right")
