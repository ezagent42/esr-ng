# PR #147 — Polish + AgentTypeRegistry removal + Message.uri → Message.id

Final cleanup PR. Picks up loose ends from S-4..S-8 + structural cleanup that depends on earlier PRs landing.

## Part A — AgentTypeRegistry removal

Per SPEC v2 §5.14 — agent flavor lives in the name prefix + the AgentTemplate (which carries kind_module). The AgentTypeRegistry's per-flavor lookup table is no longer needed at the URI dispatch layer.

### Replacement pattern

Chat plugin's `entity://` SpawnRegistry fn (added in PR #141) currently delegates to AgentTypeRegistry for the `host == "agent"` case. Replace with template-driven dispatch:

```elixir
:ok = Ezagent.SpawnRegistry.register("entity", fn 
  %URI{host: "user", path: "/" <> name} = uri ->
    DynamicSupervisor.start_child(UserSupervisor, {Ezagent.Kind.Server, {Entity.User, %{uri: uri}}})
  %URI{host: "agent"} = uri ->
    # Look up the AgentTemplate that owns this agent_uri to get kind_module
    case lookup_kind_module_for_agent(uri) do
      {:ok, mod} -> DynamicSupervisor.start_child(AgentSupervisor, {Ezagent.Kind.Server, {mod, %{uri: uri}}})
      :error -> {:error, {:no_template_for_agent, uri}}
    end
end)

# Design decision (Allen 2026-05-19): snapshot-first with template-fallback.
# Covers both restart (snapshot exists) and first-spawn (snapshot missing,
# but workspace template carries kind_module) cases.
defp lookup_kind_module_for_agent(uri) do
  uri_str = URI.to_string(uri)
  
  # Step 1: snapshot table has kind_type from a previous boot's
  # KindSnapshot.write (the Kind.Server's persistence path).
  case Ezagent.Ecto.KindSnapshot.get(uri_str) do
    %{kind_type: kt} when not is_nil(kt) ->
      {:ok, resolve_kind_module(kt)}
    _ ->
      # Step 2: scan workspace session_templates for one matching this
      # agent_uri. Templates carry an explicit kind_module field (added
      # in PR #147 to AgentTemplate schema; templates that pre-date this
      # use the legacy `class` field as a fallback).
      case Ezagent.Workspace.Store.find_template_by_agent_uri(uri_str) do
        {:ok, %{kind_module: mod}} -> {:ok, mod}
        {:ok, %{class: class}} -> {:ok, kind_module_from_class(class)}
        :error -> :error
      end
  end
end

# Helpers: resolve_kind_module/1 maps :cc → Ezagent.Entity.Agent,
# :curl → Ezagent.Entity.CurlAgent, :echo → Ezagent.Entity.Echo.
# kind_module_from_class/1 maps "cc.agent" → Ezagent.Entity.Agent, etc.
```

**Design rationale**: snapshot-first is hot-path-fast (one DB row by URI), restart-correct (snapshot is the most recent kind_type the system saw), and degrades gracefully (falls back to template scan if snapshot is missing). Template-first would be correct but slower (full table scan); using it as fallback means it only fires on first-spawn or after snapshot pruning.

The snapshot's `kind_type` field already exists today (it's the result of `kind_module.type_name/0` stored as an atom). The migration to `kind_module` field is unnecessary — `type_name` (`:cc`, `:curl`, `:echo`) is sufficient to resolve back to a module.

### Files deleted

- `apps/ezagent_core/lib/ezagent/agent_type_registry.ex`
- `apps/ezagent_core/test/ezagent/agent_type_registry_test.exs`
- AgentTypeRegistry init from `EzagentCore.Application`
- AgentTypeRegistry init from `ezagent_core/ets_owner.ex`
- All `AgentTypeRegistry.register/2` calls in plugin Applications (cc, curl, echo) — replaced by Template registration which already declares kind_module

### Files updated

- Chat plugin Application: replaces AgentTypeRegistry delegation with template-lookup
- Tests reorganized

## Part B — Message.uri → Message.id rename

Per SPEC v2 §5.13 — Message is session-internal data, not a Kind. `Message.uri` (a `message://` URI) becomes `Message.id` (plain UUID string).

### Schema migration

```sql
ALTER TABLE messages RENAME COLUMN uri TO id;
-- new format: just the UUID hex (no message:// prefix)
UPDATE messages SET id = REPLACE(id, 'message://', '');
```

Plus `messages.ref` (a URI to another message) → `messages.ref_id` (plain string):
```sql
ALTER TABLE messages RENAME COLUMN ref TO ref_id;
UPDATE messages SET ref_id = REPLACE(ref_id, 'message://', '');
```

Per §5.11 wipe-rebuild, just drop + recreate.

### Code changes

- `apps/ezagent_core/lib/ezagent/message.ex`: 
  - `field :uri` → `field :id` (still primary key, string)
  - `field :ref` → `field :ref_id` (string)
  - `new/3` generates plain UUID, no `message://` prefix
  - Update Jason.Encoder + types
- `apps/ezagent_core/lib/ezagent/message_store.ex`: `by_uri/1` → `by_id/1`
- Every reader of `msg.uri` → `msg.id`
- Every reader of `msg.ref` → `msg.ref_id`
- LV stream: `dom_id={msg.id}` not `{msg.uri}`
- Delete `message://` from `@known_schemes` (already not in SPEC §5.6 list)

## Part C — S-4 mention dropdown lists all session members

Per `entity-agnostic-architecture-reflection.md` S-4 — today mention dropdown only lists `agent://` URIs. Update to list every Session member regardless of entity sub-kind (user + agent both).

`apps/ezagent_plugin_liveview/lib/ezagent_plugin_liveview/admin_live.ex` — `list_session_agent_uris/1` → `list_session_member_uris/1`. Drop the agent-only filter. Users + agents both show up in `@-mention` dropdown.

## Part D — S-5 /admin/entities live registry page

New LV `/admin/entities` listing every KindRegistry entry with scheme/type/name columns + clickable links to per-entity detail pages (auto-derive). Replaces the agent-only `/admin/agents`.

`apps/ezagent_plugin_liveview/lib/ezagent_plugin_liveview/entities_live.ex` (new).

Keep `/admin/agents` for back-compat — filters entities to `entity://agent/*`. Or delete it per "no tails" rule.

## Part E — S-7 docstring leak audit

Grep all "the user" mentions in shared-code docstrings; rewrite as "the entity" where the code path treats users + agents uniformly.

## Part F — S-6 mix ezagent.agent.create task

Mirror `mix ezagent.user.create user://X --password Y --caps ...` with `mix ezagent.agent.create entity://agent/<flavor>_<name> --kind-module Ezagent.Entity.CurlAgent --caps ...`.

## Scope

DO: All of A through F.
DO NOT: Any new feature scope; only cleanup.

## Estimated effort

Medium — multiple separable changes, each small. Subagent ~90-120 min.
