# URI Design — current state + open questions

Status: draft for discussion (Allen ↔ uri-design subagent)
Date opened: 2026-05-19
Owner / decider: Allen

The goal is to converge every URI in the codebase to one consistent shape so plugin authors don't have to guess where the "type" lives, where a sub-resource starts, or whether a host means "identity" vs "namespace". The structural rule we already have (`<instance>[/<sub-resource>]`) is sound. What's inconsistent is **what `<instance>` looks like** scheme-by-scheme.

---

## §1 Inventory

Every URI scheme currently constructed or parsed in `apps/`. Columns:

- **Scheme** — `xxx://`
- **Instance shape** — what identifies the Kind
- **Sub-resource?** — does anything append `/...` after the instance
- **Spawned via** — registration mechanism
- **Persisted?** — does it survive a phx restart
- **Defining file** — canonical place that constructs the URI

| Scheme | Instance shape | Sub-resource | Spawned via | Persisted | Defining file (line) |
|---|---|---|---|---|---|
| `agent://` | `agent://<type>/<name>` (PR #131, typed) | `/behavior/<kind>/<action>` | `SpawnRegistry("agent")` → `AgentTypeRegistry` | yes (via Workspace.session_templates) | `apps/ezagent_core/lib/ezagent/agent_type_registry.ex:96` |
| `session://` | `session://<name>` (flat) | `/behavior/<kind>/<action>` | `SpawnRegistry("session")` | snapshot | `apps/ezagent_domain_chat/lib/ezagent_domain_chat/application.ex:176` |
| `user://` | `user://<name>` (flat) | `/behavior/identity/<action>` | `SpawnRegistry("user")` | snapshot | `apps/ezagent_domain_identity/lib/ezagent_domain_identity/application.ex:71` |
| `workspace://` | `workspace://<name>` (flat) | `/behavior/workspace/<action>` | n/a — created by Workspace API | snapshot | `apps/ezagent_domain_workspace/lib/ezagent/entity/workspace.ex:78` |
| `template://` | `template://<class>/<name>[@<hash>]` — TWO host values: `agent` (versionless) and `session` (`@hash`) | `/behavior/...` allowed in principle | `SpawnRegistry("template")` switches on `uri.host` (`agent` vs `session`) | snapshot | `apps/ezagent_domain_chat/lib/ezagent/entity/session_template.ex:136`, `apps/ezagent_domain_chat/lib/ezagent/entity/agent_template.ex:19` |
| `resource://` | `resource://uploads/<filename>` — host is a "namespace" | none today | not a live Kind — pure data ref | filesystem on disk | `apps/ezagent_plugin_liveview/lib/ezagent_plugin_liveview/admin_live.ex:230` |
| `system://` | `system://bootstrap`, `system://other` (flat sentinel) | none | not spawned — fixed sentinels | n/a | `apps/ezagent_domain_identity/lib/ezagent/entity/user.ex:24`, `apps/ezagent_core/lib/ezagent/capability.ex:10` |
| `message://` | `message://<uuid16>` (16 hex chars, auto-gen) | none | not a Kind — opaque ref | yes (messages table) | `apps/ezagent_core/lib/ezagent/message.ex:101` |
| `feishu://` | `feishu://<chat_id>` (e.g. `oc_…`) | `/behavior/chat/<action>` (Receiver Kind) | `SpawnRegistry("feishu")` | ephemeral (rule in DB points at it; spawn on demand) | `apps/ezagent_plugin_feishu/lib/ezagent/entity/feishu_chat.ex:44` |
| `pty-input://` | `pty-input://default` (singleton) | `/behavior/pty/write` | spawned at boot | ephemeral | `apps/ezagent_plugin_cc/lib/ezagent/entity/pty_input.ex:32` |
| `routing-admin://` | `routing-admin://default` (singleton) | `/behavior/routing_admin/<action>` | spawned at boot | ephemeral | `apps/ezagent_core/lib/ezagent/entity/routing_admin.ex:33` |

**Legacy / removed**:
- `curl-agent://<name>` — gone (PR #131 rewrote to `agent://curl/<name>`).
- `agent://<name>` (no type segment) — gone same PR; validate-time error.

**Notes on parse layering** (`apps/ezagent_core/lib/ezagent/uri.ex`):

- `parse!/1`'s `@known_schemes` is `~w(agent session user resource system)` — **5 schemes**.
- Reality has **11+** schemes in use (table above) plus `feishu://` and the singletons.
- So `Ezagent.URI.parse!/1` would crash on `workspace://default`, `template://session/X@hash`, `feishu://oc_xxx`, `message://abcd`, `pty-input://default`, `routing-admin://default`.
- In practice everyone uses `URI.parse/1` (stdlib) directly for these — bypassing the allowlist. The allowlist is, today, partial documentation rather than an enforced invariant.
- `instance/1` and `subresource/1` are scheme-aware via two clauses: `agent://` (path = `/<name>/<sub>...`) vs everything else (path = `/<sub>...`). `template://session/X@hash` happens to work because `subresource("/")` is empty when no further path is present, but if anyone tried `template://session/X@hash/behavior/...` the agent-style 2-segment split would incorrectly take `X@hash` as the name and `behavior/...` as sub-resource — which happens to be correct! — but only by coincidence; the code path is the "non-agent" branch which gobbles the entire path.

---

## §2 Inconsistencies

### 2.1 Authority layout — agent and template have a "type", everyone else doesn't

| Pattern | Schemes |
|---|---|
| `<scheme>://<name>` (host = identity, no sub-namespacing) | `session`, `user`, `workspace`, `message`, `feishu`, `pty-input`, `routing-admin`, `system` |
| `<scheme>://<type>/<name>` (host = type, 1st path seg = name) | `agent`, `template` |
| `<scheme>://<namespace>/<filename>` (host = namespace, 1st path seg = item id) | `resource` |

Three different "what is the host?" conventions. A plugin author writing a new scheme has to read every existing scheme to know which one applies — the convention is implicit.

### 2.2 `template://` overloads the host two ways

- `template://agent/<name>` — host="agent" means "Class is AgentTemplate", versionless.
- `template://session/<name>@<hash>` — host="session" means "Class is SessionTemplate", content-addressed via `@hash`.
- `template://session/<name>:<tag>` — same scheme, but `:tag` instead of `@hash` (mutable pointer; `apps/ezagent_domain_chat/lib/ezagent/entity/session.ex:74` mentions it but I didn't find a writer — may be design-only).

So `template://` is doing four jobs at once:
1. Saying "this is a template" (scheme).
2. Distinguishing Kinds within templates (host = "agent" vs "session").
3. Naming the template (1st path segment).
4. Optionally pinning a version (`@hash`) or tag (`:tag`).

That's the same pattern `agent://<type>/<name>` solves with the type segment — except `template://` adds versioning, which `agent://` doesn't.

### 2.3 `resource://uploads/...` uses host as a flat namespace

`resource://uploads/<filename>` has only one namespace today ("uploads"). The shape signals "I might grow more namespaces later" (`resource://snapshots/X`? `resource://logs/Y`?) but none exist. The host segment is doing the same job as `agent://`'s type but it's called something different conceptually ("namespace" vs "type") and there's no `ResourceTypeRegistry` mirror of `AgentTypeRegistry`.

### 2.4 Behavior sub-path: scheme-agnostic in spirit, scheme-specific in code

The sub-resource `/behavior/<kind>/<action>` is universal — every Kind dispatches through it. But its **starting position** in the URI depends on scheme:

- `agent://cc/demo-builder/behavior/chat/receive` — sub-path starts at `/behavior/...` which is path segment 2 (after `/<name>`).
- `session://main/behavior/chat/send` — sub-path starts at `/behavior/...` which is path segment 1 (right after host).

PR-A (PR #132) addressed the **parser** ambiguity with a positional split (the parser knows where the instance ends per scheme). But the **convention** is still scheme-specific: a fresh contributor reading `agent://X/Y/behavior/Z/W` could reasonably guess `Y` is part of the behavior path. The positional split works because of an out-of-band rule (agent has 2 instance segments, others have 1).

### 2.5 Content-addressing only exists for `template://`

`@hash` is unique to SessionTemplate. No other scheme has any version/content addressing. If, say, an Agent Kind ever wanted snapshot-immutable identity (e.g. `agent://cc/demo-builder@v3`), there's no shared convention to lean on — we'd invent it per scheme.

### 2.6 Scheme allowlist drift

`Ezagent.URI.@known_schemes` lists 5; the codebase uses 11. Anyone reaching for `Ezagent.URI.parse!/1` instead of stdlib `URI.parse/1` would hit a phantom failure. This is documentation rot, but it's also the safety net that doesn't catch anything.

### 2.7 Singleton synthetic schemes diverge from instance schemes

`pty-input://default` and `routing-admin://default` are administrative singletons. Their URIs use `default` as a stand-in for "the only one". `system://bootstrap` uses `bootstrap` for the same purpose. Three sentinels, three naming styles.

### 2.8 Class string vs URI type segment carry the same information twice

A workspace template entry looks like (DB shape):

```json
{"class": "cc.agent", "agent_uri": "agent://cc/demo-builder"}
```

The `class` field encodes "cc" again. The pre-PR-D2 split (`cc.pty` vs `cc.channel_instance`) was being collapsed into `cc.agent` because the operator-visible "mode" was scheduled to move into the URI sub-resource (or query string) and out of the class string. So the class string is shrinking as the URI absorbs more semantics. Worth asking: at the limit, does `class` exist at all, or is `agent_uri` self-describing?

### 2.9 Plugin scheme registration is by-scheme, not by-type

`SpawnRegistry.register("feishu", ...)` claims an entire scheme. `AgentTypeRegistry.register("curl", ...)` claims a sub-namespace of `agent://`. So a plugin can choose either model — own a whole new scheme, or add a type under `agent://`. The cc plugin took the type route. The feishu plugin took the whole-scheme route. They face the same architectural choice (a plugin contributing one Kind type that participates in chat) and made different decisions. Both work, but the inconsistency is real.

---

## §3 Open design questions

Each question has a default proposal and the tradeoff against alternatives.

### Q1 — Uniform 2-segment authority: should every scheme adopt `<scheme>://<type>/<name>`?

**Status quo**: `agent://cc/demo-builder` is 2-segment; `session://main`, `user://admin`, `workspace://default` are 1-segment.

**Proposal A (uniform 2-segment)**: All schemes become `<scheme>://<type>/<name>`.
- `session://generic/main` (vs `template://session/main@hash`'s class)
- `user://human/admin`, `user://service/cron-runner`
- `workspace://default/feishu-seed` (where "default" is the only Class today)
- Pro: one rule, mechanically clear.
- Con: more typing for schemes with only one Class today (`session`, `workspace`).

**Proposal B (scheme IS the type)**: Roll back PR #131 — `cc-agent://demo-builder`, `curl-agent://my-deepseek`, keep `session://main` as-is.
- Pro: scheme = type, no nested namespacing needed.
- Con: scheme allowlist grows unboundedly; PR #131 explicitly went the other way. The reason it went the other way (Allen 2026-05-19 03:21): "agent" is the noun a user thinks in; "cc" / "curl" is implementation flavor. Mixing them in the scheme conflates user-facing identity with backend wiring.

**Proposal C (status quo + document)**: Keep current layout. Document the rule as: schemes with multiple implementations of the same noun use `<scheme>://<type>/<name>`; single-implementation schemes stay flat.
- Pro: minimal change.
- Con: every new scheme is a judgment call. The Feishu plugin chose "whole new scheme" because it's a fundamentally different noun from agent; `template://` chose "single scheme, host = class" because templates ARE templates. Either decision works locally; the global picture is harder to teach.

### Q2 — Should `template://` be split or kept unified?

**Status quo**: `template://agent/<name>` (versionless) and `template://session/<name>@<hash>` (versioned) — same scheme, different shape based on host.

**Proposal A (split)**: `agent-template://<name>` + `session-template://<name>@<hash>`. Per Q1-B, scheme = Kind.
- Pro: each scheme has one shape.
- Con: more schemes; "they're both templates" semantically.

**Proposal B (uniform 2-seg)**: Keep `template://<class>/<name>`; require `@hash` always (even for AgentTemplate). Today AgentTemplate is versionless because it's "human-edited" (`apps/ezagent_domain_chat/lib/ezagent/entity/agent_template.ex:19`). Forcing a hash unifies the shape but loses the human-edited model.
- Pro: every template URI has the same shape.
- Con: AgentTemplate would need a versioning model it doesn't currently want.

**Proposal C (status quo + ban tags)**: Drop the never-implemented `template://session/X:<tag>` shape, document the explicit two-shape rule.

### Q3 — Behavior sub-path: positional vs query string

**Status quo**: `agent://cc/X/behavior/chat/say` — the `/behavior/...` is path, position depends on scheme.

**Proposal A (query string)**: `agent://cc/X?action=chat.say` — sub-resource becomes a query, parser is trivially scheme-agnostic.
- Pro: parser becomes scheme-agnostic. Capability matchers stay positional-on-instance.
- Con: route table syntax (`/behavior/chat/receive`) is everywhere. Big migration. `URI.to_string/1` puts query after path → still readable but different shape.

**Proposal B (always 2-segment authority for instance)**: Same as Q1-A. Then `/behavior/...` always starts at path[1]. No query needed.

**Proposal C (status quo + positional split)**: Already done in PR-A (PR #132). The parser is correct. The only cost is the implicit per-scheme rule.

### Q4 — `resource://` namespace: real generalization or de facto singleton?

**Status quo**: Only `resource://uploads/<filename>` exists. The host segment is reserved for future namespaces (`snapshots`, `logs`, etc.) — none exist yet.

**Proposal A (commit to namespacing)**: Add a `ResourceNamespaceRegistry` mirror of `AgentTypeRegistry`. Plugins register a namespace + fetcher.
- Pro: lays the groundwork for "any plugin can expose downloadable assets".
- Con: speculative — only one namespace today.

**Proposal B (collapse to flat)**: Drop the host segment — `resource://<filename>` with a flat uploads-only namespace. Add the host back when a second namespace shows up.
- Pro: simplest. Currently the only consumer is admin_live.ex line 230.
- Con: forward-incompatible breakage when (if) we add snapshots/logs.

**Proposal C (status quo + document)**: Keep the shape, document that `resource://<namespace>/<id>` is the convention and any plugin adding a namespace registers an unpacker.

### Q5 — Singleton sentinel naming: `default` vs `bootstrap` vs ???

**Status quo**: `pty-input://default`, `routing-admin://default`, `system://bootstrap`. Three sentinels, two names.

**Proposal**: Pick one. `default` for "the singleton instance of this Kind"; reserve `system://` for capability/audit sentinels where the sentinel name carries meaning (`system://bootstrap`, `system://migration-pr131`, `system://admin-override`).

### Q6 — Plugin scheme contribution: when do you own a scheme vs add a type?

**Status quo**: implicit. Feishu owns `feishu://`. Cc and Curl share `agent://`.

**Proposal**: Document the rule as a triangle. A plugin should:
- Own a scheme when its Kind is a distinct **noun** from anything in core (e.g. `feishu://` is a chat-platform receiver, not an agent).
- Add a type under an existing scheme when its Kind is a **flavor** of an existing noun (e.g. `agent://cc/...` is a flavor of agent).
- Anything else (e.g. plugin-supplied templates, plugin-supplied resources) extends an existing namespace via a sub-registry (TemplateRegistry, ResourceNamespaceRegistry).

This is the **plugin isolation north star** rule made specific to URIs.

### Q7 — `@hash` content addressing: only template, or extend?

**Status quo**: `template://session/X@hash` is the only content-addressed URI. Snapshot URIs, message URIs, agent URIs are all opaque identity (UUID or human name).

**Proposal A (extend to other versioned things)**: Allow `<scheme>://<type>/<name>@<hash>` anywhere a Kind has a content-versioned identity (future: blueprint snapshots, frozen agent configs).

**Proposal B (status quo)**: Keep `@hash` template-only; it's the only Kind whose identity is its content.

### Q8 — Should `Ezagent.URI.@known_schemes` be the source of truth?

**Status quo**: It lists 5 schemes; reality has 11+. It's documentation drift.

**Proposal A (close the loop)**: Have `SpawnRegistry.register/2` also call `Ezagent.URI.register_scheme/1`. The allowlist becomes a runtime ETS table fed by plugins. `Ezagent.URI.parse!/1` consults it. Singletons like `pty-input` register themselves at boot.

**Proposal B (delete the allowlist)**: It catches nothing — remove it from `parse!/1` and just delegate to stdlib `URI.parse/1`.

---

## §4 Discussion log

(Discussion appended here as it progresses. Newest entry at top within this section.)

---

## §5 Final spec

(Empty until consensus reached.)
