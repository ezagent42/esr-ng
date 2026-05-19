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

### 2026-05-19 — Round 2: Workspace X confirmed + routing-admin rethink + feishu confirmation

**Workspace → X (Deployment Unit) ✓**

Allen confirms X and extends the scope hierarchy: `global ⊂ workspace ⊂ session ⊂ user/resource/...`

**Clarifying note on the extension.** "session ⊂ user/resource/..." conflates two ideas worth separating:

- **Scope = "where the rule applies"** — global / workspace / session. These are containment relationships (a session is inside a workspace; a workspace is inside global). A rule scoped to session://Y fires only when the dispatch is "within" Y.
- **Matcher condition = "what the rule matches on"** — caller URI, receiver URI, mention, etc. These filter WHICH dispatches inside a scope fire. `{type: mention, arg: agent://X}` is a matcher; it doesn't need user:// to be a scope level.

Today's `routing_rules.matcher_data` already lets a rule say "fires only when caller is user://Z" via the `from` matcher. So "user/resource as a scope level" is already expressible as a matcher condition WITHIN session/workspace/global. Adding them as scope levels would duplicate.

**Recommendation: scope levels stay 3 (global ⊂ workspace ⊂ session). Per-user / per-resource targeting stays a matcher condition.** Cleaner separation of concerns, no duplication.

If Allen actually wants user-scoped rules (e.g. "user Z has their own private rule table independent of any session"), that's a different feature — call it user preferences or per-user routing overrides — and worth designing as such, not by overloading scope.

**Q5 routing-admin rethink ✓ (Allen's alternative is cleaner)**

Allen: "为什么需要 routing-admin singleton 注入，而不是 `workspace://xxx/routing?action=add_rule&operator=xxx`?"

He's right — the singleton was a v1 expedient. Better model:

- **Workspace-scoped rule mutation**: dispatch to `workspace://X?action=routing.add_rule` (under Q3 query string). Cap check naturally scoped (caller needs `routing.add_rule` cap on `workspace://X`).
- **Global rule mutation**: dispatch to `system://routing?action=add_rule`. `system://` is already in @known_schemes; carries "this is platform-level, requires platform caps".
- **Session-scoped (per S-10)**: dispatch to `session://Y?action=routing.add_rule`.

**`routing-admin://default` synthetic singleton goes away.** Workspace + Session + System Kinds acquire a `routing` Behavior. Cleaner, eliminates a synthetic Kind, makes cap-scoping match the rule's actual scope.

Same logic applies to `pty-input://default` — it's another v1 synthetic singleton. PTY input dispatch could be `agent://cc/X?action=pty.write` (the input goes to the agent it targets, not to a global PTY-input singleton). PR-G candidate.

**Q6 feishu re-shape confirmed ✓**

Allen: "本来的考虑就是最好是向 `user://xxx/?feishu_id=oc_xxx` 发送，从而能复用 user/agent 本来已有的 behavior"

Exactly the target. The shape:

- **Sending to a user via feishu**: `user://X?action=chat.send&feishu_id=oc_xxx` (or, cleaner, the feishu_id is metadata in the Invocation args, not the URI query). The user binding lookup happens in the feishu plugin's outbound Behavior; the URI just identifies the user.
- **Sending to a session via feishu**: `session://Y?action=chat.send`. The session's feishu binding (the chat_id) is a sub-resource OR a UserBinding lookup — feishu plugin handles the side-channel.
- **`feishu://oc_xxx` Kind**: deleted. Receiver Behavior moves to register on User Kind (or Session Kind, for room-targeted receives).

**What this means concretely:**
- No more "feishu_user_bindings table is the source of truth for feishu_id → user_uri." That table stays as-is (a join table), but the URI shape changes.
- Existing routing rules referencing `feishu://oc_xxx` get rewritten by migration to the user/session URI form.
- KindRegistry entries for `feishu://*` go away.

Impact: substantial migration + plugin refactor. Worth doing in PR-F as planned. Risk is BroadcastInvariantTests for the feishu fan-out path — the plugin's Receiver Kind is currently a Process that holds an inbox; if Behavior moves to User, the inbox semantics need re-homing on the User process (which already has Identity Behavior — add Feishu Behavior alongside).

**Q4 (resource:// namespace) — now answerable under X + Q1 outcomes:**

Resources are platform-level downloadable assets that don't belong to any one workspace (uploads, snapshots, logs all cross workspaces). Resource URI shape per Q1: `resource://<type>/<id>`. Today: `resource://uploads/<filename>`. Future: `resource://snapshots/<id>`, `resource://logs/<id>`. ResourceNamespaceRegistry mirroring AgentTypeRegistry — plugin registers a `<type>` + fetcher. Decision A from §3 Q4.

---

### 2026-05-19 — Round 1: Allen's first pass

**Allen's verdicts on the 8 questions:**

| Q | Allen's call | Note |
|---|---|---|
| Q1 — uniform `<scheme>://<type>/<name>` | **Yes, uniform** | "多打几个 default 没问题" (an extra `default` path segment is fine) |
| Q2 — split `template://` or unify | **Unify with `@hash`** | Agent templates should ALSO be versioned |
| Q3 — `/behavior/...` path vs query string | **Query string** | "位置式指定资源，动作是 query" — path identifies the resource, action is a query param |
| Q4 — `resource://` namespace meaning | **Deferred** | Pending workspace discussion below |
| Q5 — singleton sentinel naming | **Open** | Allen: "我没有看明白，routing-admin:// 的路径是怎么回事？" — see clarification below |
| Q6 — plugin scheme vs type | **All plugins are core flavors** | "不应该有任何 plugin 不是 core 的风味" — `feishu://` is the wrong shape. `user://X/feishu/openid` or `session://X/feishu/chat_id` instead |
| Q7 — `@hash` extension | **Templates only** | "其它的好像没有知道内容版本的需要" |
| Q8 — `@known_schemes` as SoT | **Yes, lock down bypass paths** | Allowlist becomes load-bearing |

**Q5 clarification (asked by Allen):** `routing-admin://default` is a **synthetic singleton Kind**. It exists so routing rule mutations can dispatch through the regular cap-check pipeline. Source: `apps/ezagent_core/lib/ezagent/entity/routing_admin.ex:7`:

> "All routing rule mutations (add/delete/disable/enable) now go through `Ezagent.Invocation.dispatch` to `routing-admin://default/behavior/routing_admin/<action>`, which fires the Phase 3d real CapBAC check at dispatch step 5.5."

Dispatch target shape: `routing-admin://default/behavior/routing_admin/<action>`. The `default` is the singleton instance name (since there's only one routing-admin per cluster, the name doesn't carry meaning — it's a placeholder). Same pattern as `pty-input://default`.

Under Q3's query-string outcome, the path collapses to: `routing-admin://default?action=routing_admin.add_rule`. Even cleaner: under Q1's uniform 2-segment + Q3's query, sentinels become `routing-admin://singleton/default?action=...` — `singleton` as the type segment, `default` as the (still placeholder) instance name. Allen's "default vs bootstrap" question reduces to: pick ONE word for "the placeholder instance of a singleton Kind". Recommendation: `default`.

**Q6 follow-through (feishu re-shape):**

If `feishu://oc_xxx` becomes `session://X/feishu/chat_id` (or `user://X/feishu/openid`), then:

- The `feishu://oc_xxx` Receiver Kind shape goes away. Instead, the `session://X` Kind acquires a `feishu` sub-resource path that the feishu plugin's Behavior registers against (mirroring how `/behavior/<kind>/<action>` works today, but for plugin-supplied side-effects).
- The `feishu_user_bindings` table either stays as-is (a join table — fine, no scheme change needed) or its row keys become path-segment fragments under `user://X`.
- Existing `feishu://X` URIs in `KindRegistry`, routing rules, audit log need migration.

**This is a substantial refactor** — separate PR (call it PR-F). The URI design lock-in justifies it: keeping `feishu://` as a top-level scheme cements the "plugin can carve out its own world" anti-pattern.

### Open follow-up — Workspace's role (Allen's deferring Q4 to this)

Allen asks: **"workspace 究竟是做什么的？为什么我们需要独立的 workspace，而不是直接类似 Template 那样，提供 SessionWorkspace, UserWorkspace 这些具体的使用概念，workspace 当作文件夹使用？"**

**What workspace actually does today** (code reading):

`apps/ezagent_domain_workspace/lib/ezagent/entity/workspace.ex:1-22`:
> A `workspace://<name>` URI carries (a) a set of member Entity URIs that should be alive whenever the Workspace is "instantiated", (b) a list of session templates, (c) routing rules scoped to this Workspace. It is the **plugin-isolation north star** in action: a future plugin author adds a new Kind X, declares it in a Workspace template, and on cluster restart their Kind X comes back without any change to ezagent_core.

So workspace serves **two functions**:

1. **Declarative**: "when this instance boots, ensure these entities are alive + these templates are loaded + these rules are installed."  This is the bootable-config role; not a folder.

2. **Routing scope**: at dispatch time, the bound workspace_uri filters which routing rules apply. `apps/ezagent_domain_chat/lib/ezagent/behavior/chat.ex:127-137` resolves session_uri → workspace_uri via WorkspaceRegistry, passes that to the rule evaluator.

Allen's "as folder" framing probes whether workspace is **one concept too many**. Three coherent answers:

**Answer X — keep workspace as a Kind, clarify its role.** Workspace is "the unit of bootable configuration + the routing scope unit". Not a folder; a declaration. Document this. (Status quo with clearer framing.)

**Answer Y — collapse workspace into a tag-only concept.** Drop the Workspace Kind entirely. Replace with a `workspace: string` field on each entity. Rule scoping becomes `routing_rules.workspace = "X"`. The "boot-time guarantee that entities are alive" becomes a separate concept (a Manifest? a Deployment?). Lighter; less ceremony.

**Answer Z — replace workspace with per-type containers (Allen's suggestion).** `SessionWorkspace` holds sessions + their routing. `AgentWorkspace` holds agents that should be alive. `UserWorkspace` holds users (?). Each type has its own organizational unit.

**Trade-offs:**

- Y is the most reductive: workspace becomes a string. Lightest model; question is whether "I want these N agents alive at boot" needs a Kind to express, or just a field.
- Z splits concerns by entity type. Pro: clearer per-type semantics. Con: cross-type concerns (a routing rule that says "messages from this user go to this agent in this session" — which container owns it?) become ambiguous. SessionWorkspace? AgentWorkspace? Both?
- X keeps workspace as the "deployment unit" — clearer if we frame it like Kubernetes Namespace: a tenant boundary for shipped configuration.

**My recommendation: X with explicit re-framing.** Workspace is the **deployment unit** — like a tenant or a project root. SessionTemplate is the **conversation recipe** (one instance gets cloned per spawn). Workspace and SessionTemplate are different shapes:

- Workspace: "this is what should be alive after `mix phx.server`". One per cluster usually; multiple if you tenant by team/project.
- SessionTemplate: "this is what a conversation should look like when instantiated by an orchestrator". Many per workspace.

Under this framing:

- The routing-rule scope hierarchy becomes natural: global ⊂ workspace ⊂ session.
- S-10 (session-scoped rules) lands cleanly.
- SessionTemplate inherits the workspace's routing rules at save time (the working-copy captures them), and fork-instantiates them under the new session_uri scope (per S-10's session_uri column).

But: this is my read, not a decision. Allen's question is structural and deserves an explicit pick before Q4 (`resource://` namespace) gets answered, because if workspace becomes Y or Z, resource:// gets pulled in the same direction.

---

---

## §5 Final spec

Consensus shape after Rounds 1-3 (Allen 2026-05-19). This section is **normative**. Every claim here is a constraint that downstream PRs (#139-#145) and future code must satisfy.

### §5.1 Authority — uniform 2-segment

Every Ezagent URI has the same authority shape:

    <scheme>://<type>/<name>

- `<scheme>` is a registered Ezagent scheme (see §5.6).
- `<type>` is a registered sub-type within that scheme. For schemes that today look "flat" (`user://admin`), the `<type>` is the literal string `default` (so the canonical form is `user://default/admin`). **No shorthand** — operators must type the canonical form (Allen 2026-05-19: no backward compatibility, see §5.11).
- `<name>` is the instance identity within `<scheme>/<type>`. UUIDs, human names, hashes all OK — opaque to the parser.

**Forbidden**: 1-segment authorities (`user://admin` without canonicalization), 3+ segment paths (`agent://cc/X/extra`), per-plugin top-level schemes (see §5.6).

### §5.2 Sub-resource — query string for action; path is identity

Action invocation uses a query parameter, not a path suffix:

    <scheme>://<type>/<name>?action=<behavior>.<action>

- `?action=<behavior>.<action>` selects the Behavior + action to invoke (e.g. `?action=chat.send`).
- Path stays the identity. The previous `/behavior/<kind>/<action>` syntax is deprecated and migrated by PR #144.
- Args to the action travel in the Invocation struct, NOT in the URL. The URL identifies the target + the verb; args are payload.

**Path attributes (sub-resources on the resource itself, e.g. `/quota`, `/acl`) are NOT allowed.** Such attributes become Behaviors on the Kind, accessed via the action query string (`?action=quota.get`).

### §5.3 Content addressing — templates only

Templates carry a `@<hash>` suffix on the name segment:

    template://session/<name>@<hash>
    template://agent/<name>@<hash>

This is the ONLY sanctioned use of `@<hash>`. Other Kinds use opaque identity (UUID, human name, ETS-assigned).

### §5.4 Scope hierarchy — global ⊂ workspace ⊂ session

Routing rules are scoped to exactly one of three levels:

| Scope | `routing_rules` column shape | Where rules apply |
|---|---|---|
| Global | `workspace_uri IS NULL`, `session_uri IS NULL` | Every dispatch in the cluster |
| Workspace | `workspace_uri = "workspace://X"`, `session_uri IS NULL` | Every dispatch in any session bound to workspace X |
| Session | `workspace_uri IS NULL`, `session_uri = "session://Y"` | Every dispatch in session Y |

Rules at different scopes COMPOSE additively at dispatch time (the rule evaluator walks all three layers).

**Matcher conditions** (`caller = user://Z`, `mention = agent://X`, etc.) are SEPARATE from scope and live in `matcher_data`. Per-user / per-resource filtering is a matcher condition, not a scope level.

### §5.5 Workspace = Deployment Unit (not folder, not container)

A Workspace is the **bootable configuration unit** — the declaration of what entities should be alive and what templates/rules should be installed after `mix phx.server`. Analogous to a Kubernetes Namespace or a tenant root.

Workspace is NOT:
- A folder (it has runtime semantics; folders don't)
- A container OWNING its members (a session belongs to a workspace via WorkspaceRegistry.bind, but the session can be unbound and rebound without destruction)
- Per-type (one Workspace Kind, not SessionWorkspace + AgentWorkspace + UserWorkspace)

Most clusters have ONE Workspace. Multi-tenant deployments have N.

### §5.6 Scheme allowlist — `@known_schemes` is the source of truth

`Ezagent.URI.@known_schemes` is the single canonical list. The list is fed at runtime by `SpawnRegistry.register/2` (so plugins extending it is a deliberate, audited act). `Ezagent.URI.parse!/1` rejects URIs whose scheme is not in the list.

Schemes that exist in this canonical list (post-PR-#143):

| Scheme | Purpose | Type segments registered today |
|---|---|---|
| `agent://` | Conversational entities | `cc`, `curl`, `echo` |
| `user://` | Human entities | `default` (canonical) |
| `session://` | Chat rooms | `default` (canonical) |
| `workspace://` | Deployment units | `default` (canonical) |
| `template://` | Content-addressed recipes | `agent`, `session` |
| `resource://` | Platform-level addressable assets | `uploads`, future: `snapshots`, `logs` |
| `message://` | Message envelopes | `default` (canonical, UUID name) |
| `system://` | Platform sentinels | `routing`, future: `bootstrap`, `migration-<id>` |

**Plugins MUST NOT introduce a new top-level scheme.** Plugin Kinds are either:
- A flavor of an existing entity (register a new `<type>` under `agent://`, `user://`, etc.)
- A side-channel binding on an existing entity (no URI; metadata in the entity's slice)

This kills the `feishu://` anti-pattern (see §5.8).

### §5.7 Synthetic singletons — dissolved

The `routing-admin://default` and `pty-input://default` "synthetic singleton Kind" pattern is removed:

- Routing rule mutation dispatches to the rule's actual scope-owning Kind:
  - Workspace rules → `workspace://default/X?action=routing.add_rule`
  - Session rules → `session://default/Y?action=routing.add_rule`
  - Global rules → `system://routing/default?action=add_rule`
- PTY input dispatches to the target agent: `agent://cc/X?action=pty.write`.

Workspace, Session, System, and Agent Kinds each acquire the relevant Behavior. The cap check naturally scopes to the rule's actual target instead of a synthetic placeholder.

### §5.8 Feishu re-shape (and the general plugin-side-channel rule)

A plugin that connects Ezagent to an external system (Feishu, Slack, etc.) MUST NOT own a top-level scheme. The plugin:

- Registers a Behavior on the existing core Kind (User for per-user channels, Session for per-room channels).
- Stores its external-system identifier (feishu_open_id, slack_user_id, etc.) as metadata — either in the entity's slice or in a side join table.
- Receives + sends through the core Kind's existing dispatch path.

Concrete target shape for Feishu:

- Sending to a user via Feishu: `user://default/X?action=chat.send` with `feishu_id` in the Invocation args.
- Sending to a room via Feishu: `session://default/Y?action=chat.send`; the feishu plugin's outbound side-channel looks up the room's binding.

`feishu://oc_xxx` Kind is deleted (PR #141). Existing routing rules / KindRegistry entries / audit-log mentions are migrated.

### §5.9 Resource — flat URI; soft workspace binding via slice field

Resources are platform-level addressable assets: `resource://<type>/<id>` (e.g. `resource://uploads/<filename>`).

- **URI shape is always flat.** No scope or workspace embedded in the URI path/query.
- **Soft workspace binding (when needed)**: the resource's slice/snapshot carries an optional `workspace_uri` field. Allen-confirmed pattern. Dispatch can read it for quota / ACL / cleanup decisions. URI stays flat; the binding is metadata.
- Attributes (quota, ACL, lifetime) become Behaviors on the resource Kind, accessed via `?action=quota.get` etc. NOT path sub-segments.
- **Hard binding (deferred)**: should a future requirement demand strict workspace isolation at the URI layer (e.g. cluster-wide tenant separation), migrate to `workspace://default/X/resource/<type>/<id>`. Out of scope for v1.

### §5.10 Singleton naming — `default`

The canonical placeholder name for a singleton instance of a Kind is `default`. (E.g. `user://default/admin` if Allen ever supports an "admin user type", or `system://routing/default` for the global routing-rule mutator.)

`bootstrap` is reserved for cap-bearing sentinels where the name carries meaning: `system://routing/bootstrap` would imply a special migration-time variant.

### §5.11 No backward compatibility — clean rebuild

Allen 2026-05-19: existing DB data is wiped + rebuilt; no operator ergonomic shorthand, no legacy URI form accepted anywhere. Every URI everywhere — CLI input, LV form input, stored data, audit log, KindRegistry, routing matchers — is canonical (`<scheme>://<type>/<name>`) from day 1.

Concrete consequences:

- `Ezagent.URI.parse!/1` rejects un-canonical input (no `default`-injection logic).
- LV form fields show only the canonical form; placeholders are canonical.
- The SPEC migration PRs (#140-#146) carry **no legacy-URI rewrite migrations**. They carry schema changes (add columns, drop tables) and code changes. To pick up the new schema on existing dev DBs: `mix ezagent.db.reset` (drops + recreates + reseeds).

The earlier "operator ergonomic shorthand" exception is retracted.

---

## §6 Migration sequence

Each PR is independently shippable + reversible (data) / forward-only (code) where noted.

| PR | Title | Scope | Reversible? |
|---|---|---|---|
| #139 | Entity-agnostic load-bearing 3-piece (S-1+S-2+S-3) | login/cap/token + naming | Code: yes (rename + new fn); data: no schema change |
| #140 | Scope hierarchy + session-scoped rules + SessionTemplate fork replay (S-9+S-10) | `routing_rules.session_uri` column + spawn_from_template install + UI unify | Code: yes; data: yes (additive column) |
| #141 | Feishu re-shape (Q6) | delete `feishu://` Kind; Receiver Behavior on User | Code: NO (removes Kind); data: rewrite migration |
| #142 | Delete synthetic singletons (Q5 + PR-G) | routing-admin + pty-input deleted; Behaviors moved to Workspace/Session/System/Agent | Code: yes if staged; data: rewrite migration |
| #143 | `@known_schemes` runtime ETS + parse!/1 lockdown (Q8) | SoT enforcement | Code: yes; no data |
| #144 | Query-string action syntax (Q3) | `/behavior/X/Y` → `?action=X.Y` everywhere | Code: yes (large); data: rewrite migration for stored URIs |
| #145 | Polish — S-4..S-8 from reflection §4 | mention dropdown, /admin/entities, docstrings, etc. | Code: yes; no data |

**Sequencing rationale**:
- #139-140 are foundation (entity vocab + scope model) — must land first; everything else builds on them.
- #141-142 are deletes that depend on §5.6 + §5.7 being agreed.
- #143 locks in §5.6 once all schemes are stable.
- #144 is the biggest code change — last so it has the fewest dependencies still moving.
- #145 is polish — any-time, low-priority.

**Cross-cutting**: ARCHITECTURE.md + GLOSSARY.md + IMPLEMENTATION_ROADMAP.md + prototype-design-prompt.md (EN+ZH) get updated alongside the matching PR. They're not their own PR — they ship with the code change they document.
