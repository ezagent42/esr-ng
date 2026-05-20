# Phase 9 — Tenant Isolation Design (SPEC v3 of URI / Capability / Dispatch)

> **Status**: DRAFT — 2026-05-21. Authored by next-session developer
> per Phase 9 handoff at `/tmp/phase-9-handoff-prompt.md`. Allen is
> AFK; pre-made decisions from the framing doc
> (`docs/notes/workspace-as-deployment-unit.md`) carried forward
> verbatim. Open questions explicitly listed in §10.

## 0. Why Phase 9

`docs/notes/workspace-as-deployment-unit.md` defines workspace as the
**deployment unit**. Today (Phase 8c) workspace isolates 70% — session
ownership, routing rules, session templates, members. The remaining
30% (entities, capabilities, cross-workspace dispatch, persistence,
auth) is what Phase 9 closes.

After Phase 9, the deployment-unit promise is structural rather than
operational. Two workspaces on the same host cannot see each other's
users, agents, sessions, messages, or caps without an explicit
cross-workspace cap. Auth carries workspace context. Migration to
multi-host deployment becomes a runtime/operational change, not an
architectural one.

## 1. Goals

1. **Per-workspace entity URI** — every `entity://` URI carries its
   workspace as a path segment (Option A from framing doc).
2. **Per-workspace capability scoping** — `Ezagent.Capability` gains a
   `workspace_uri` field; cap matcher rejects cross-workspace use
   unless the caller holds `cross-workspace:dispatch`.
3. **Cross-workspace dispatch policy** — `Ezagent.Invocation.dispatch/1`
   adds an isolation step: caller's workspace must equal target's
   workspace OR caller holds the cross-workspace cap.
4. **Tenant-aware auth** — login derives `current_workspace_uri` from
   `current_entity_uri`; workspace dropdown becomes a real context
   switcher (gated by cross-workspace cap).
5. **Per-workspace data isolation** — `workspace_uri` column on
   sessions / messages / invocations / snapshots / caps tables;
   read filters enforce isolation; write asserts.

## 2. Non-Goals

- **No multi-host deployment.** Phase 9 makes multi-host possible
  later; doing it is Phase 10+.
- **No per-workspace database/schema.** Single shared SQLite for now;
  isolation is a column, not a tablespace.
- **No workspace-level rate limiting or quotas.** Future.
- **No `user://` / `agent://` URI revival.** SPEC v2 deletion stands.
- **No back-compat shim for pre-Phase-9 URI shapes.** Wipe + rebuild
  per memory `feedback_let_it_crash_no_workarounds`.
- **No session/template URI shape change.** Phase 9 touches `entity://`
  only. Sessions stay bound via `WorkspaceRegistry`; unifying all
  schemes to a single 3-segment shape is SPEC v4 / Phase 10.
- **No "system-scoped" sentinel workspace.** Every entity lives in a
  real workspace; system-wide privileges flow through caps, not URI.
- **No multi-workspace membership.** A given entity URI belongs to
  exactly one workspace. To act in two workspaces, create two
  entities (or hold a cross-workspace cap from one).

## 3. URI shape — SPEC v3 (entity scheme only)

### 3.1 New shape

    entity://<type>/<workspace_name>/<entity_name>

| Today (SPEC v2)              | Phase 9 (SPEC v3)                         |
|------------------------------|-------------------------------------------|
| `entity://user/admin`        | `entity://user/default/admin`             |
| `entity://user/allen`        | `entity://user/team-alpha/allen`          |
| `entity://agent/echo_default`| `entity://agent/default/echo_default`     |
| `entity://agent/cc_demo`     | `entity://agent/team-alpha/cc_demo`       |

- `<type>` ∈ `{user, agent}` (closed set; SPEC v2 §5.12 unchanged).
- `<workspace_name>` is the workspace's bare name (the `<name>`
  segment of a `workspace://<name>` URI). Must match the regex
  `^[a-z][a-z0-9_-]*$` (lowercase + digits + dash + underscore;
  workspace creation already enforces this; Phase 9 codifies as
  URI-parse-time check).
- `<entity_name>` keeps its existing free-form contract (lowercase,
  flavor-prefixed for agents: `cc_demo`, `curl_my-thing`,
  `echo_default`).

### 3.2 Parser change

`Ezagent.URI.parse!/1` extension for `entity://`:

- Accepts ONLY 3-segment authority path (`/<workspace>/<name>`) —
  2-segment paths (`/admin`) are rejected with
  `ArgumentError: entity URI must include workspace segment`.
- Rejects 4+ segments (`/<workspace>/<entity>/<sub>`) — sub-resource
  positions are reserved (SPEC v2 §5.1 said "future named
  sub-resources"; Phase 9 keeps that hold).

`Ezagent.URI.instance/1` for `entity://`:

- Returns the full 3-segment path stripped of query/fragment:
  `entity://user/default/admin?action=identity.list_caps` →
  `entity://user/default/admin`.

### 3.3 New helper: `entity_workspace_uri/1`

```elixir
@spec entity_workspace_uri(URI.t()) :: URI.t()
def entity_workspace_uri(%URI{scheme: "entity", path: "/" <> rest}) do
  [workspace_name, _entity_name] = String.split(rest, "/", parts: 2)
  URI.new!("workspace://" <> workspace_name)
end
```

Used by:
- Dispatch (`§5`) to extract caller / target workspace.
- LiveAuth (`§6`) to derive `current_workspace_uri` from
  `current_entity_uri`.
- Cap matcher (`§4.2`) to enforce workspace dimension.

### 3.4 Persistent storage

- DB columns holding entity URIs (caps, audit, users, agents,
  workspace memberships, message authorship, etc.) store the full
  3-segment string. No migration scripts that "split" old data —
  wipe + rebuild.

### 3.5 Why URI-carries-workspace (Option A) not ambient context (Option B)

Per framing doc §"Per-workspace entity URIs" — Option A:

- The URI tells you everything; no out-of-band lookup needed.
- Auth tokens carry full URI; tenant context travels with the
  principal.
- Same handle in two workspaces is two distinct entities (clean
  isolation).
- Cap matching can extract workspace from URI string at O(1).

Option B (`%{workspace: ws_uri}` in dispatch envelope) was rejected:
ambient context is easy to forget; cap matcher would need a 2-key
lookup; data leak risk if envelope isn't validated.

## 4. Capability — workspace dimension

### 4.1 Struct change

```elixir
defstruct [
  :kind,
  :behavior,
  :instance,
  :workspace_uri,   # NEW — %URI{scheme: "workspace"} | :any
  :granted_by,
  :granted_at
]

@type t :: %__MODULE__{
  kind: atom() | :any,
  behavior: module() | :any,
  instance: URI.t() | :any | scope_tuple(),
  workspace_uri: URI.t() | :any,   # :any only for cross-workspace caps
  granted_by: URI.t(),
  granted_at: DateTime.t()
}
```

- `workspace_uri` is **required** on construction (no default `:any`).
- `:any` is reserved for the bootstrap admin cap and explicit
  cross-workspace grants. The structurally-required path is the
  concrete workspace URI.
- Programmatic call sites that previously built a `Capability` MUST
  now pass `workspace_uri:` — compile-time enforced via
  `@enforce_keys`.

### 4.2 Matcher change

```elixir
def matches?(%__MODULE__{} = cap, %{kind: k, behavior: b, instance: i, workspace_uri: w}) do
  field_match?(cap.kind, k) and
    field_match?(cap.behavior, b) and
    instance_match?(cap.instance, i) and
    workspace_match?(cap.workspace_uri, w)
end

defp workspace_match?(:any, _), do: true
defp workspace_match?(%URI{} = held, %URI{} = needed),
  do: URI.to_string(held) == URI.to_string(needed)
defp workspace_match?(_, _), do: false
```

- `Ezagent.Capability.cap_for_action/3` extended: derives `needed`
  workspace from the target URI via `URI.entity_workspace_uri/1`
  when target is an entity, or via `WorkspaceRegistry.lookup/1`
  when target is a session.

### 4.3 Grant API change

```elixir
# Before:
Ezagent.Identity.grant_cap(entity_uri, %{kind: ..., behavior: ..., instance: ...}, granter_uri)

# After:
Ezagent.Identity.grant_cap(
  entity_uri,
  %{kind: ..., behavior: ..., instance: ..., workspace_uri: workspace_uri_or_any},
  granter_uri
)
```

- The granter's workspace defaults the grantee's workspace if not
  specified (most caps are intra-workspace).
- Cross-workspace grant requires the granter to hold
  `cross-workspace:dispatch` AND pass `workspace_uri: :any` or a
  workspace URI different from their own. Caught at grant-time, not
  use-time — fail loudly.

### 4.4 Bootstrap admin cap

The structural invariant per Decision #81 becomes:

```elixir
%Ezagent.Capability{
  kind: :any,
  behavior: :any,
  instance: :any,
  workspace_uri: :any,        # cross-workspace by structural design
  granted_by: URI.parse("system://bootstrap/default"),
  granted_at: ...
}
```

`Ezagent.Capability.admin_invariant?/1` updated to require
`workspace_uri: :any` in addition to the existing three-:any pattern.

### 4.5 User self-cap default

`Ezagent.Entity.User.default_caps/0` (Decision #133 / invariant 6)
returns a cap scoped to the user's workspace:

```elixir
def default_caps(workspace_uri) do
  [%Ezagent.Capability{
    kind: :session,
    behavior: :any,
    instance: :any,
    workspace_uri: workspace_uri,   # NOT :any
    granted_by: URI.parse("system://bootstrap/default"),
    granted_at: DateTime.utc_now()
  }]
end
```

A user can chat in their own workspace by default; cross-workspace
chat requires an explicit cross-workspace cap.

## 5. Cross-workspace dispatch policy

### 5.1 New cap

```elixir
%Ezagent.Capability{
  kind: :any,
  behavior: :any,
  instance: :any,
  workspace_uri: :any,    # the structural cross-workspace marker
  granted_by: ...,
  granted_at: ...
}
```

This is the same shape as the admin invariant cap. A
**non-admin cross-workspace cap** would narrow `kind` / `behavior` /
`instance` but keep `workspace_uri: :any`.

Convention: a cap whose `workspace_uri == :any` is a
**cross-workspace cap**. This is intentionally rare and
admin-managed.

### 5.2 Dispatch step

`Ezagent.Invocation.dispatch/1` gains a new step between cap-check
(step 5.5) and target-resolution:

```
5.6 Workspace isolation check:
    caller_ws = URI.entity_workspace_uri(ctx.caller)  # or WorkspaceRegistry.lookup if session
    target_ws = workspace_of(invocation.target)
    cond do
      caller_ws == target_ws -> :ok
      Enum.any?(ctx.caps, &cross_workspace?(&1)) -> :ok
      true -> {:error, :cross_workspace_denied}
    end
```

- `cross_workspace?/1` returns true when `workspace_uri == :any` AND
  the cap still authorizes the action (i.e., already passed step
  5.5).
- Denial returns `:cross_workspace_denied` (NEW error atom) to
  distinguish from `:unauthorized`. Inbound transports surface as a
  distinct error message per invariant 9.

### 5.3 Workspace-of resolver

```elixir
defp workspace_of(%URI{scheme: "entity"} = uri),
  do: Ezagent.URI.entity_workspace_uri(uri)

defp workspace_of(%URI{scheme: "session"} = uri) do
  case Ezagent.WorkspaceRegistry.lookup(uri) do
    {:ok, ws} -> ws
    :error -> raise "session #{uri} has no workspace binding (invariant 4 violated)"
  end
end

defp workspace_of(%URI{scheme: "workspace"} = uri), do: uri
defp workspace_of(%URI{scheme: "system"} = _uri), do: :system_scope
```

`:system_scope` skips workspace isolation entirely — system schemes
(routing, bootstrap) are cross-cutting by design.

### 5.4 Invariant test

`apps/ezagent_core/test/invariants/cross_workspace_isolation_test.exs`:

- Setup: 2 workspaces (default, team-alpha), 1 user per workspace,
  each holding default caps.
- Assert: `entity://user/default/admin` cannot dispatch
  `chat.send` to `entity://agent/team-alpha/cc_demo` →
  `{:error, :cross_workspace_denied}`.
- Assert: grant admin the cross-workspace cap → same dispatch
  succeeds.
- Assert: revoke → dispatch fails again.

## 6. Tenant-aware auth

### 6.1 Login flow

`EzagentWeb.SessionPrincipal.put/2` (single sanctioned writer for
`:current_entity_uri`) gains a side-effect: it also writes
`:current_workspace_uri`, derived from the entity URI's workspace
segment.

```elixir
def put(conn, raw) when is_binary(raw) do
  canonical = canonicalize(raw)
  entity_uri = URI.parse(canonical)
  workspace_uri = Ezagent.URI.entity_workspace_uri(entity_uri)

  conn
  |> configure_session(renew: true)
  |> put_session(:current_entity_uri, canonical)
  |> put_session(:current_workspace_uri, URI.to_string(workspace_uri))
end
```

### 6.2 Bare-handle canonicalization

The Phase 8c bare-handle path
(`SessionPrincipal.canonicalize("admin")` → `"entity://user/admin"`)
now requires a workspace. Two options for the bare-handle UX:

- **A** — Default workspace: bare `"admin"` →
  `"entity://user/default/admin"`. Fast, no UI surface for
  workspace.
- **B** — Workspace-qualified: bare `"admin"` rejected; user must
  type `"default/admin"` or `"team-alpha/admin"`.

**Recommended A** — default workspace fallback at canonicalize-time;
the login form gets a secondary "Workspace" optional field
(defaults to `default`). This keeps the bare-handle ergonomics
Phase 8c built.

### 6.3 LiveAuth on_mount

`EzagentWeb.LiveAuth.on_mount/3` reads BOTH session slots and assigns:

```elixir
socket
|> assign(:current_entity_uri, parsed_entity)
|> assign(:current_workspace_uri, parsed_workspace)
```

LV scopes (live_session :require_entity) inherit both.

### 6.4 Workspace selector = logout + re-auth (Allen correction 2026-05-21)

**Amended from original SPEC.** Per Allen's structural correction: if
entity URI is workspace-bound (3-segment), then
`entity://user/default/admin` and `entity://user/team-alpha/admin`
are **two different entities**. There is no "stay-as-this-user,
change-workspace" semantic in this design — switching workspace IS
switching entity.

The avatar-dropdown workspace selector behaves as:

- Click another workspace → POST `/workspaces/switch` with target ws.
- Controller clears BOTH `:current_entity_uri` AND
  `:current_workspace_uri` from the session.
- Redirect to `/login?workspace=<target_ws>` with the workspace
  pre-filled in the login form.
- User authenticates as the entity in that workspace
  (`<handle>` is interpreted as `entity://user/<target_ws>/<handle>`
  via the same `SessionPrincipal.canonicalize/1` path but with a
  workspace-override option).

Why this is the right model:

- **The URI tells you everything (Option A)** — if workspace is in
  the URI, then "current entity" already pins the workspace. Having
  a separate "current workspace" assign that can diverge from
  `entity_workspace_uri(current_entity_uri)` would be a structural
  inconsistency.
- **Cross-workspace cap is for DISPATCH, not impersonation** — admin
  in `default` workspace with the cross-workspace cap can SEND a
  message TO an agent in `team-alpha`. They cannot BECOME the admin
  in `team-alpha` — that requires authenticating as that distinct
  entity.
- **Auditability** — every action's `ctx.caller` is unambiguously
  one workspace's entity. No ambient "operating workspace" overlay
  to forget about.

Note on the redundant assign: `:current_workspace_uri` is still
written by `SessionPrincipal.put/2` (§6.1) because LV scopes read
it directly without re-parsing the entity URI on every render — it's
a derived cache. But it MUST always equal
`entity_workspace_uri(current_entity_uri)`; an invariant test
asserts this.

### 6.5 SessionPrincipal codebase invariant updated

The existing invariant test
(`session_principal_test.exs:101 — no direct put_session(:current_entity_uri, _)`)
extends to:

- No direct `put_session(:current_workspace_uri, _)` outside
  `SessionPrincipal.put/2` and the workspace-switch controller's
  clear path.
- New invariant test: `:current_workspace_uri` ==
  `entity_workspace_uri(:current_entity_uri)` for any session where
  both are set.

## 7. Data isolation — per-tenant table columns

### 7.1 Tables that gain `workspace_uri`

| Table              | Purpose                              | Notes                          |
|--------------------|--------------------------------------|--------------------------------|
| `caps`             | Identity slice persistence           | NEW column; derived from cap struct |
| `sessions`         | Session Kind persistence (Snapshot)  | Already implicit via Workspace.Loader; promote to explicit column |
| `messages`         | MessageStore                         | NEW column; copies from session's workspace |
| `invocations`      | Audit log                            | NEW column; derived from caller+target |
| `snapshots`        | Per-Kind on-change snapshots         | NEW column; derived from owning Kind URI |
| `users`            | User Kind base table                 | NEW column; derived from URI |
| `agents`           | Agent Kind base table                | NEW column; derived from URI |
| `routing_rules`    | Already has `workspace_uri`          | No change |
| `workspaces`       | Workspace.Store                      | No change (workspace itself isn't tenant-scoped) |
| `templates`        | SessionTemplate/AgentTemplate        | NEW column; templates are per-workspace |

### 7.2 Read-time filter

Every read query against a per-tenant table MUST scope by
`workspace_uri = ?`. Pattern (Ecto):

```elixir
def list_messages(session_uri, %URI{} = workspace_uri) do
  from(m in Message,
    where: m.session_uri == ^session_uri and
           m.workspace_uri == ^URI.to_string(workspace_uri)
  )
  |> Repo.all()
end
```

Helper: `Ezagent.Persistence.scope_by_workspace/2` centralizes the
where-clause to make audit trivial.

### 7.3 Write-time assertion

Inserts MUST set `workspace_uri`; an Ecto changeset rule rejects nil.
A separate test asserts no `insert(... %{workspace_uri: nil})` call
sites exist via grep gate.

### 7.4 Invariant test

`apps/ezagent_core/test/invariants/per_tenant_tables_have_workspace_column_test.exs`:

- Iterates registered schemas; asserts every per-tenant table has a
  `workspace_uri` column (or is on the explicit exemption list:
  `workspaces`, `system_*`).
- Future schema addition without `workspace_uri` fails this test
  immediately.

## 8. Migration plan — wipe + rebuild

Per `feedback_let_it_crash_no_workarounds` and SPEC v2 §5.11
precedent.

### 8.1 Migration sequence

1. **Drop dev DB** (`apps/ezagent_core/priv/repo/data/*.db`).
2. **Reset Ecto migrations** if needed (the actual table schemas
   change — `workspace_uri` column adds + entity URI string format).
3. **Boot phx** — `Ezagent.Workspace.create("default", %{})` (PR-M
   idempotent seed) runs first; admin + echo_default seeded into
   `workspace://default` with the new URI shape.
4. **Run invariant tests** to confirm clean state.

### 8.2 Production-data caveat

ezagent is pre-v1.x; no production deployments. The wipe-rebuild
choice has no user-data impact. **If this ever changes**, a Phase 10
"namespacing migration" with backfill scripts becomes a separate
work item.

### 8.3 Documentation update

- `ARCHITECTURE.md` Decision Log: append Decision #145 (URI SPEC v3
  + per-workspace entity scoping) with WHY + DRIFT DEFENSES.
- `docs/notes/uri-design.md` §5: append `§5.15 — Per-workspace
  entity URIs (SPEC v3, Phase 9)`. Keep §5.12 (entity:// merge)
  intact; v3 extends not replaces.
- `.claude/skills/ezagent-developer/SKILL.md`:
  - Update invariant 11 to note 3-segment for entities.
  - Add invariant 13: cross-workspace dispatch requires
    `cross-workspace:dispatch` cap.
  - Update §"Anti-patterns": "I'll write a workspace-scoped cap
    without the workspace_uri field" → refuse.
- `docs/notes/workspace-as-deployment-unit.md`: change "30% gap →
  Phase 9" prose into "100% — Phase 9 closed the gap on
  <YYYY-MM-DD>". Bilingual `.zh_cn.md` sync.

## 9. PR sequence (6 PRs)

| PR | Title | LOC est. | Depends on |
|----|-------|----------|------------|
| 1  | SPEC + framing-doc updates + Decision Log entry | 600 (doc only) | — |
| 2  | URI v3 parser + entity migration (wipe + seed) + invariant test | 900 | 1 |
| 3  | Capability workspace dimension + grant API + admin invariant update | 700 | 2 |
| 4  | Cross-workspace dispatch enforcement + cap + invariant test | 600 | 3 |
| 5  | Tenant-aware auth + workspace switcher + UI gating | 800 | 4 |
| 6  | Data isolation columns + read filters + write assertions + invariant test | 1200 | 5 |

After PR-6, Phase 9 is "done" by the invariant-test criterion (per
memory `feedback_completion_requires_invariant_test`): the 4 new
invariant tests fail closed if any of the 6 PRs' work is reverted or
drifts.

### PR-1 deliverables

- This SPEC file + `.zh_cn.md` translation.
- `docs/notes/uri-design.md` §5.15 stub (full content in PR-2 once
  parser exists).
- `ARCHITECTURE.md` Decision #145 stub.
- No code changes.

### PR-2 deliverables

- `Ezagent.URI.parse!/1` enforces 3-segment entity authority.
- `Ezagent.URI.instance/1` returns 3-segment for entity scheme.
- New `Ezagent.URI.entity_workspace_uri/1` helper.
- DB wipe + `mix ezagent.seed.bootstrap` rebuilds admin + echo_default
  in `workspace://default`.
- All hardcoded URI strings updated (audit shows ~30 call sites in
  tests + ~5 in lib code).
- `Ezagent.Entity.User.admin_uri/0` returns
  `URI.new!("entity://user/default/admin")`.
- New invariant test
  `apps/ezagent_core/test/invariants/entities_have_workspace_test.exs`.
- All existing tests updated + green.

### PR-3 deliverables

- `Ezagent.Capability` adds `workspace_uri` to `@enforce_keys`.
- `Ezagent.Capability.matches?/2` workspace check.
- `Ezagent.Capability.cap_for_action/3` derives needed workspace.
- `Ezagent.Identity.grant_cap/3` signature carries workspace.
- All existing cap construction sites updated.
- `Ezagent.Capability.admin_invariant?/1` requires `workspace_uri: :any`.
- All cap tests updated + green.

### PR-4 deliverables

- `Ezagent.Invocation.dispatch/1` step 5.6 inserted.
- `:cross_workspace_denied` error atom + propagation.
- Cap helper `cross_workspace?/1`.
- Inbound transport (Feishu, future) surfaces denial with distinct
  reaction emoji per invariant 9.
- Invariant test
  `apps/ezagent_core/test/invariants/cross_workspace_isolation_test.exs`.

### PR-5 deliverables

- `EzagentWeb.SessionPrincipal.put/2` writes both session slots.
- `EzagentWeb.LiveAuth` on_mount assigns both URIs.
- `/workspaces/switch` POST endpoint + controller + cap check.
- Workspace dropdown wires to switch endpoint.
- `EzagentWeb.SessionPrincipal` invariant test extends to
  `:current_workspace_uri`.
- Tests for switch + login derivation.

### PR-6 deliverables

- Ecto migration: `workspace_uri` column added to 8 tables.
- Schemas: `workspace_uri` field on each module.
- Read filters via `Ezagent.Persistence.scope_by_workspace/2`.
- Changeset rules: required field assertion.
- Invariant test
  `apps/ezagent_core/test/invariants/per_tenant_tables_have_workspace_column_test.exs`.
- Grep gate: no nil writes.

## 10. Open questions (small)

These are intentionally narrow — most decisions are pre-made by
framing doc + this SPEC. Allen can override any during PR review.

- **Q1 — Bare-handle login behavior (§6.2)**: A (default workspace
  fallback) or B (workspace-qualified required)? **Recommended A**.
- **Q2 — Workspace-switch session-slot semantics (§6.4)**: ~~My
  original read: NO — identity is fixed; workspace is a
  scope-of-action.~~ **Allen corrected 2026-05-21: YES, switching
  workspace clears BOTH `:current_entity_uri` AND
  `:current_workspace_uri`.** Reason: entity URI is workspace-bound
  (3-segment); `entity://user/default/admin` and
  `entity://user/team-alpha/admin` are distinct entities. There is
  no "stay-as-this-user, change-workspace" semantic. Switch
  redirects to `/login?workspace=<target>`. See §6.4 for the
  amended flow.
- **Q3 — Granter's workspace default for cross-workspace grants
  (§4.3)**: when admin grants a cap, should the cap default to
  granter's workspace OR grantee's workspace? **Recommended
  grantee's workspace** — the grantee is the principal who'll use
  the cap. Granter must pass `workspace_uri: <grantee_ws>` or
  `:any` explicitly.
- **Q4 — Workspace name reserved words**: `_system`, `admin`,
  `default`, `system`. Should the workspace creation form reject
  any of these as new workspace names? **Recommended yes for
  `_system` and `system` (forward-compatibility) and no for
  `admin` / `default` (already in use as workspace name on
  bootstrap)**.

## 11. Verification checklist

After all 6 PRs land, the following must hold:

1. `entity://user/admin` rejected by `Ezagent.URI.parse!/1` with
   "must include workspace segment".
2. `entity://user/default/admin` parses; `entity_workspace_uri/1`
   returns `URI.new!("workspace://default")`.
3. `Ezagent.Capability` struct has 6 fields; construction without
   `workspace_uri:` fails compile (`@enforce_keys`).
4. `Ezagent.Identity.grant_cap("entity://user/default/admin", %{...,
   workspace_uri: ws}, granter)` succeeds; the cap appears in
   `list_caps_for/1` output with the workspace dimension preserved.
5. Two-workspace-two-user invariant test
   (`cross_workspace_isolation_test.exs`) passes: cross-workspace
   dispatch fails closed without the cross-workspace cap.
6. Login as admin → session has BOTH `:current_entity_uri` and
   `:current_workspace_uri`.
7. Workspace-switch POST without cap → 403; with cap → session
   updated.
8. SQLite query: `SELECT count(*) FROM messages WHERE workspace_uri
   IS NULL` returns 0 in fresh DB.
9. `mix test --include slow` green (no leftover Phase 8c tests
   broken by URI shape change).

## 12. Out of scope (to Phase 10+)

- Per-workspace SQLite databases (multi-tenant SaaS deployment).
- Workspace export / import / migration tooling.
- Workspace-level quotas (max sessions, max API keys, etc.).
- Multi-workspace membership (a user appearing in two workspaces
  with one identity).
- Unifying URI shape across all schemes (session://, template://,
  resource:// also gain workspace segment) — SPEC v4.
- Workspace billing / usage reporting.

---

## Implementation pointer

After PR-1 lands, the next session should use
`superpowers:subagent-driven-development` per
`feedback_subagent_must_load_project_skills` (subagent prompts MUST
load `Skill: ezagent-developer` + `Skill: elixir-phoenix-helper`).

Branch strategy: feat branch off main (e.g.
`feat/phase-9-tenant-isolation`), each PR squash-merged. Promote
pattern from `feedback_promote_dev_to_main` if main has diverged.
Admin-merge pre-authed (`feedback_admin_merge_authorized`).
