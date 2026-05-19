# PR #144 — Dissolve synthetic singletons (`routing-admin://`, `pty-input://`)

Per SPEC v2 §5.7 — the `routing-admin://default` and `pty-input://default` synthetic singleton Kind pattern is removed. Behaviors move to the actual scope-owning Kinds (Workspace / Session / System / Agent).

## routing-admin://default → scope-aware routing rule mutation

Today: `Behavior.RoutingAdmin` with actions `:add_rule`, `:delete_rule`, `:enable_rule`, `:disable_rule`. Dispatched to `routing-admin://default/behavior/routing_admin/<action>`. Cap check uses the routing-admin URI as target — no relationship to which workspace/session the rule actually scopes.

After: dispatch goes to the rule's scope-owning Kind:
- Workspace rule mutation → `workspace://default/<X>/behavior/routing/<action>` (Workspace Kind acquires `Behavior.Routing`)
- Session rule mutation → `session://<template>/<X>/behavior/routing/<action>` (Session Kind acquires `Behavior.Routing`)
- Global rule mutation → `system://routing/default/behavior/routing/<action>` (System Kind for global ops; pre-existing `system://` scheme used)

`Behavior.Routing` is shared across the three Kinds — same actions, different cap scope. The action body checks the URI scheme to decide which scope to write the rule under.

Cap names change: today `routing_admin.add_rule` is granted on `routing-admin://default`. After, `routing.add_rule` is granted on `workspace://default/X` (or session://Y, or system://routing/default). Migration rewrites cap rows.

## pty-input://default → agent-direct PTY write

Today: `Behavior.Pty` action `:write` registered on `Entity.PtyInput`. Dispatched to `pty-input://default/behavior/pty/write` with `agent_uri` in args. The Pty.write Behavior looks up the agent's PtyServer pid by agent_uri.

After: dispatch goes directly to the target agent. `entity://agent/cc_X/behavior/pty/write` with the input bytes in args. Same Pty.write Behavior, now registered on `Entity.Agent` (or just on `cc_*` flavored agents). The agent_uri is the dispatch target itself — no `agent_uri` arg needed.

## Files touched

### Delete (or reduce)
- `apps/ezagent_core/lib/ezagent/entity/routing_admin.ex` — delete module
- `apps/ezagent_core/lib/ezagent/behavior/routing_admin.ex` — rename to `Ezagent.Behavior.Routing`, generalize
- `apps/ezagent_plugin_cc/lib/ezagent/entity/pty_input.ex` — delete module
- `apps/ezagent_plugin_cc/lib/ezagent/behavior/pty.ex` — keep, re-register on Entity.Agent (cc flavored)
- `apps/ezagent_core/lib/ezagent_core/application.ex` — drop routing-admin spawn
- `apps/ezagent_plugin_cc/lib/ezagent/plugin_cc/application.ex` — drop pty-input spawn; register Pty Behavior on Agent
- `apps/ezagent_core/lib/ezagent/uri.ex` — drop `routing-admin` + `pty-input` from @known_schemes (already correct per SPEC §5.6)

### Update
- `apps/ezagent_plugin_liveview/lib/ezagent_plugin_liveview/routing_live.ex` — dispatch targets change (workspace/session/system instead of routing-admin)
- `apps/ezagent_plugin_liveview/lib/ezagent_plugin_liveview/pty_terminal_live.ex` — dispatch target changes (agent URI instead of pty-input)

### Caps migration
- `apps/ezagent_core/priv/repo/migrations/<TS>_pr144_dissolve_synthetic_singletons.exs`:
  - For each Capability row with `kind = :routing_admin`, replace with three rows: one each for workspace/session/system scopes
  - For each Capability row with `kind = :pty_input`, replace with a per-agent cap (or wildcard agent cap if widespread)
  - Drop snapshots / KindRegistry entries for routing-admin://, pty-input:// (they're :ephemeral so just won't respawn)

## Verification

- Routing UI at /admin/routing still works: add rule, dispatch, audit log shows dispatch to `workspace://X/behavior/routing/add_rule` (not routing-admin)
- PTY web terminal still works: type input, sees output. Audit log shows dispatch to `entity://agent/cc_X/behavior/pty/write`
- `KindRegistry.list_all` no longer shows routing-admin:// or pty-input:// entries

## Scope (this PR only)

DO: dissolve routing-admin + pty-input. Move Behaviors.
DO NOT: change @known_schemes runtime ETS (PR #145). Don't touch query-string syntax (PR #146).

## Estimated effort

~10 files, 1 schema migration, cap-table rewrite. Subagent ~60 min.
