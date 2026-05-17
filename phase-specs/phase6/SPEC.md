# Phase 6 — Production Hardening

**Status:** **DRAFT** 2026-05-17. Awaiting Allen review per spec-review-checklist.md.

**Theme:** Take v0 demo-quality system to "small team can use it in production". Close Phase 5's known gap (v1→v2 CC channel wire swap), land ESR_HOME DB migration, fill the multi-user routing gap, articulate the three-layer (core/domain/plugin) boundary in code + docs + CI.

## North star

After Phase 6, a small team (Allen + 3-5 others) can:
- Each log in as their own user with cap-scoped permissions (not just admin)
- Use ESR via LV + CLI + Feishu, all consistent — same caps, same routes, no admin bypass
- Have CC instances connect from their own laptops via the new production WS channel (Phase 1 prototype gone)
- Run their own deployment from `~/.esr-ng/<profile>/` without polluting the git repo
- Trust that future plugin authors can add new adapters without breaking the canonical operator UX

## Source

- `IMPLEMENTATION_ROADMAP.md §9` (post-Phase-5 sketch)
- Allen 2026-05-17 directives:
  - "multi-user 加入 Phase 6"
  - "cc_channel + cc_pty 保持独立"
  - "core/plugin 还有第三层 Domain"
  - "Federation defer — 跟 multi-tenant 一起 brainstorm"
  - "UI 也算 domain（canonical operator surface）"
- Companion docs: `docs/notes/post-phase-5-meta-report.md`, `docs/notes/spec-review-checklist.md`, `docs/notes/plugin-receiver-kind-contract.md`

## Three-layer model (locked in 2026-05-17 brainstorm)

| Layer | Content | Who owns |
|---|---|---|
| **core** | Protocols + mechanisms: URI / Invocation / Behavior contract / Kind contract / 4 Registry / Snapshot.Writer / Audit / ReadyGate / Idempotency / Capability struct / **UI.Form behaviour** / Esr.Runtime / Esr.Home / CCEvents / Routing.Matcher AST / Resolver / RuleStore | ESR team — plugin authors don't read it |
| **domain** | Canonical biz primitives + canonical operator UIs: Chat Behavior + Session/Agent Kind / Identity Behavior + User Kind / Workspace Kind + Loader / RoutingAdmin Kind / concrete matchers (mention/from/in_session/text_*) / DefaultRules / MentionRouting+SessionRouting tables / **CLI engine + Mix.Tasks.Esr shell** / **LV pages** | ESR team — plugin authors import but cannot change |
| **plugin** | Adapters + instances: esr_plugin_feishu / esr_plugin_cc_pty / esr_plugin_cc_channel / esr_plugin_cc_bridge_v1_prototype / esr_plugin_echo / future esr_plugin_slack/discord/react_spa/htmx_ui/... | Anyone — adding/removing one doesn't affect others |

## Decisions (defaults; no Allen blocking)

| # | Question | Default |
|---|---|---|
| P6-D1 | CC v2 wire transport: Phoenix.Channel WS vs raw WS | Phoenix.Channel (matches v0.4 §8 invariant #8 "CC channel via stdio… BUT v2 uses Channel handshake per Roadmap §8 5b") |
| P6-D2 | v1_prototype removal timing: same PR as v2 vs deferred | Same PR — atomic swap. v1 routes deleted, all wire goes through v2. Simpler than "keep both for migration period" (no migration users yet) |
| P6-D3 | ESR_HOME DB migration: copy-and-switch vs symlink vs in-place rename | `mix esr.home.adopt_db` task: copy current `esr_core_dev.db` → `$ESR_HOME/<profile>/db/esr_core.db`, update config to read from ESR_HOME (with env var fallback), verify boot, then operator deletes old file manually (we don't auto-delete) |
| P6-D4 | DB path source-of-truth: hardcoded config vs env-only | env-driven via `Esr.Home.path(:db) <> "/esr_core.db"`; config/runtime.exs reads at boot. No hardcoded path strings. (Allen 2026-05-17 directive: "不要写死路径编码,路径以 ESR_HOME 变量为 base 动态组合") |
| P6-D5 | CLI auth: cookie-based (same as Erlang dist) vs per-CLI-user token | reuse Erlang cookie at the distribution layer (operator who can read cookie file = admin); per-non-admin-user token is Phase 7 (when CLI federation arrives). v1 CLI = single-operator-per-machine assumption |
| P6-D6 | Feishu user cap-grant UI: per-user form vs bulk | Per-user form (small N, simpler); same UI surface as `/admin/users` add-cap |
| P6-D7 | Workspace-scoped routing rules: extend `routing_rules.workspace_uri` column vs separate `workspace_routing_rules` table | Extend with new nullable `workspace_uri` column. NULL = global rule (current behavior). Set = scoped. Resolver filters per-session-workspace at lookup time |
| P6-D8 | Multi-Feishu-app support: keep singleton Client GenServer vs per-app | Per-app GenServer keyed by `app_id`; `EsrPluginFeishu.Client.send_text/3` takes app_id arg. Credentials file becomes `feishu.yaml` with multiple app entries (back-compat: single-app shorthand) |
| P6-D9 | Domain layer file layout: one `apps/esr_domain/` vs split per subdomain | Split per subdomain (`apps/esr_domain_chat/`, `apps/esr_domain_identity/`, `apps/esr_domain_workspace/`, `apps/esr_domain_cli/`, `apps/esr_domain_web/`, `apps/esr_domain_lv/`). Each ~300-1500 LOC, individual umbrella apps so deps are explicit |
| P6-D10 | Layer purity CI: how to enforce "plugin doesn't bypass domain" | New test `apps/esr_core/test/invariants/layer_purity_test.exs`: grep plugin sources for imports — if a plugin imports `Esr.Routing.RuleStore` directly (bypassing domain's RoutingAdmin) it fails. Whitelist via `# layer-purity-exempt: <reason>` |

## PR plan (6 PRs + 1 doc + 1 boundary cleanup = 8 total)

| PR | Theme | Layer touched | LOC est |
|---|---|---|---|
| 1 | **6b** ESR_HOME DB migration (`mix esr.home.adopt_db` + config refactor) | core + domain | ~200 |
| 2 | **6h.1** Boundary cleanup part 1: rename `esr_plugin_chat` → `esr_domain_chat`, add `apps/esr_domain_identity/` (move User+Users+Identity+Capability.Parser out of core), add `apps/esr_domain_workspace/` (move Workspace+Loader+RoutingAdmin out of core) | core ↘ domain (extract) | ~50 (mostly moves; rare actual code) |
| 3 | **6h.2** Boundary cleanup part 2: rename `esr_cli` → `esr_domain_cli`, `esr_web` → `esr_domain_web`, `esr_web_liveview` → `esr_domain_lv`. Add CI invariant `layer_purity_test.exs` | rename + CI | ~150 (mostly mix.exs/test updates) |
| 4 | **6a** CC channel v1→v2 wire swap: add `Esr.PluginCcChannel.ChannelServer` Phoenix.Channel + WS endpoint; cutover Esr.PluginCcChannel Template Class's instantiate; **delete `esr_plugin_cc_bridge_v1_prototype`** | plugin | ~500 (new WS path); ~-460 (delete v1) |
| 5 | **6c.1** Multi-user routing infrastructure: per-rule `applies_to_users: [user_uri] \| nil` (nil = all). Resolver filters at lookup against `ctx.caller`. /admin/routing UI gains optional users field | domain | ~250 |
| 6 | **6c.2** Feishu user cap-grant UI: `/admin/users/feishu` LV — list `user://feishu/*` users, per-row "grant chat.send cap" button. `Esr.Users.grant_cap/2` helper | domain + plugin | ~200 |
| 7 | **6d** Workspace-scoped routing rules + multi-Feishu-app: add `workspace_uri` column to `routing_rules` (migration); Resolver scopes by session's parent workspace; `feishu.yaml` accepts multiple app entries; `EsrPluginFeishu.Client` keyed by app_id | core + plugin | ~300 |
| 8 | **6h.3 + closeout** Boundary cleanup doc: update ARCH §17 (three-layer rule), GLOSSARY (new "domain layer" entry), ROADMAP (status Phase 6 complete) | docs | ~100 |

**Total ~1750 LOC** (excluding ~-460 from v1 deletion). Each PR has an invariant test + admin merge after green.

## Invariant tests (per `feedback_completion_requires_invariant_test`)

- **PR 1 (DB migration)**: `mix esr.home.adopt_db` against a sample SQLite → run `Esr.Workspace.Store.list_all/0` from new path → returns same rows
- **PR 2/3 (boundary)**: `layer_purity_test.exs` fails when a plugin imports a `Esr.Routing.RuleStore` direct call (whitelist exempt only via comment marker)
- **PR 4 (CC v2)**: 100 messages sent through new WS path → 100 audit rows + 100 actual CC stdin writes (same gate as PR #40)
- **PR 5 (multi-user routing)**: rule `applies_to_users: [user://alice]` → message from user://alice triggers it, message from user://bob doesn't
- **PR 6 (Feishu cap-grant)**: non-admin user with `chat.send` cap can send via Feishu adapter without `:unauthorized`
- **PR 7 (workspace scoping)**: same matcher in two workspaces → only fires for the matching workspace's session
- **PR 8 (doc closeout)**: skim test (no functional assertion) — Allen review

## SPEC_REVIEW walkthrough (per docs/notes/spec-review-checklist.md)

### A. Architecture alignment
- **A1**: Roadmap §9 (Phase 6 entry) — added in PR #52
- **A2**: ARCH §5.4 (RoutingRegistry), §5.5 (additive rules), §9 (Template), §17 (will be updated by PR 8), Decisions #21+#22 (Behavior=plugin) — Phase 6 contests these by introducing domain layer
- **A3**: Decision Log entries that govern: #21+#22 (will be revised by PR 2's domain extraction)

### B. Plugin shape
- **B1 Receiver Kind**: CC v2 ChannelServer is a stateful Kind (each CC instance = an `Esr.Entity.CcChannel` Kind). Behavior `:input`/`:receive` route through dispatch. Old v1's HTTP announce → Kind spawn is gone; v2 uses Phoenix.Channel join handshake which creates the Kind on connect
- **B2 Boot order**: cc_channel plugin starts AFTER esr_domain_chat (depends on Session). Same boot-ordering pattern as cc_pty
- **B3 Storage**: ESR_HOME credentials (cc-channels.yaml unchanged); SQLite for routing_rules + users; ETS for RoutingRegistry + ReadyGate; GenServer for ChannelServer per-instance state

### C. Invariant tests
- Listed above. Per-PR gate.

### D. User-assist steps (per `feedback_flag_user_assist_steps`)
- **PR 1 DB migration**: Allen runs `mix esr.home.adopt_db` once on his machine, verifies, deletes old `esr_core_dev.db`. NOT automated (data loss risk if rushed)
- **PR 4 CC v2**: Allen restarts any local CC bridges with the new attach command. v1 disconnects on PR merge; minor disruption
- **PR 6 Feishu cap-grant**: Allen grants caps for each Feishu user that should be able to send. UI provides the surface but he's the only admin
- **PR 7 multi-Feishu**: Allen provisions additional Feishu apps in `feishu.yaml` (operator action)

### E. Drift defenses
- **PR 2/3** themselves ARE drift defense (boundary cleanup with CI)
- `layer_purity_test.exs` becomes the third Layer-2 CI gate (after `routing_consolidation_invariant_test` and `receiver_kind_pattern_test`)
- Memory `feedback_phase_planning_reads_main_docs` enforces SPEC review for Phase 7+

## Non-goals (deferred to Phase 7+)

- **Federation MVP** — bundled with multi-tenant brainstorm later
- **Plugin scaffolder** (mix esr.gen.plugin) — needs ≥3 third-party plugins to be useful
- **Per-non-admin CLI user token** — assumes CLI federation, which is Phase 7+
- **CC channel hot-migration** (v1 → v2 with zero downtime) — atomic cutover is fine for current operator scale (just Allen)
- **Pty-Web for non-cc-pty agents** — current Pty-Web (Phase 5 PR 4) handles cc-pty only; extending to general PTY-managed processes is Phase 7+
- **Workspace clone / template publish** — not needed for small-team v1
- **Audit log retention / GDPR / etc** — none of these in v0/Phase 6 scope

## Open questions for Allen

1. **D9 (one esr_domain vs split)** — I picked split. Easy to reverse if you'd rather have a single `apps/esr_domain/` with subdirs.
2. **D7 (workspace_uri column vs separate table)** — I picked column. Concerns?
3. **PR order** — I put 6b DB first, 6h.1+6h.2 next (cleanup before adding new). 6a (CC v2) after the cleanup so v2 can ship as a plugin against the cleaned-up domain. Concerns?
4. **6c.1 routing per-user**: design specifies `applies_to_users: [uri]` on rules. Should it instead be per-session-membership (caller must be in session's members) for simpler semantics? Currently the explicit list seems more flexible but more complex
