# PR #145 — `@known_schemes` runtime ETS + `parse!/1` lockdown

Per SPEC v2 §5.6 — the scheme allowlist becomes a runtime ETS table fed by `SpawnRegistry.register/2`, eliminating the documentation drift between `@known_schemes` hardcoded list vs. actual registrations.

## Change

`Ezagent.URI.@known_schemes` (compile-time list) → `Ezagent.URI.SchemeRegistry` (runtime ETS).

### New module `Ezagent.URI.SchemeRegistry`

```elixir
defmodule Ezagent.URI.SchemeRegistry do
  @moduledoc "ETS-backed source of truth for registered schemes."

  @table :ezagent_scheme_registry

  def init do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    :ok
  end

  def register(scheme) when is_binary(scheme) do
    :ets.insert(@table, {scheme})
    :ok
  end

  def registered?(scheme) when is_binary(scheme) do
    :ets.member(@table, scheme)
  end

  def list_all do
    :ets.tab2list(@table) |> Enum.map(fn {s} -> s end) |> Enum.sort()
  end
end
```

Wire in `EzagentCore.Application`:
```elixir
:ok = Ezagent.URI.SchemeRegistry.init()
# Seed with platform-controlled schemes (entity, workspace, session,
# template, resource, system) at boot — plugins extend at their
# own boot via SpawnRegistry.register/2 which now also registers
# the scheme.
for s <- ~w(entity workspace session template resource system),
    do: Ezagent.URI.SchemeRegistry.register(s)
```

### Update `Ezagent.SpawnRegistry.register/2`

When a plugin registers a spawn fn for scheme `S`, ALSO call `Ezagent.URI.SchemeRegistry.register(S)`. This is the lockdown — schemes can only be added via this audited path.

### Update `Ezagent.URI.parse!/1`

```elixir
def parse!(s) when is_binary(s) do
  case URI.new(s) do
    {:ok, %URI{scheme: nil}} ->
      raise ArgumentError, "URI missing scheme: #{inspect(s)}"
    {:ok, %URI{scheme: scheme} = u} ->
      if Ezagent.URI.SchemeRegistry.registered?(scheme) do
        u
      else
        raise ArgumentError,
              "URI scheme #{inspect(scheme)} not registered. Known: #{inspect(Ezagent.URI.SchemeRegistry.list_all())}"
      end
    {:error, part} ->
      raise ArgumentError, "URI parse failed at #{inspect(part)}: #{inspect(s)}"
  end
end
```

Delete `@known_schemes` module attribute (the hardcoded list goes away).

## Lockdown checks

Add a startup invariant test: after all plugins start, `Ezagent.URI.SchemeRegistry.list_all()` MUST match the SPEC §5.6 expected set (entity, workspace, session, template, resource, system + any plugin-added). If a plugin tries to register `feishu` after PR #143, the test fails.

Strict mode option: `Application.get_env(:ezagent_core, :scheme_lockdown, true)` — when true, parse!/1 also rejects URIs whose scheme is not in the explicit SPEC §5.6 list (no plugin extension at all). Default off; useful for prod hardening.

## Files touched

- `apps/ezagent_core/lib/ezagent/uri.ex` — remove @known_schemes, route through SchemeRegistry
- `apps/ezagent_core/lib/ezagent/uri/scheme_registry.ex` — new
- `apps/ezagent_core/lib/ezagent_core/application.ex` — init + seed
- `apps/ezagent_core/lib/ezagent_core/ets_owner.ex` — register the new ETS table
- `apps/ezagent_core/lib/ezagent/spawn_registry.ex` — co-register scheme on register/2
- `apps/ezagent_core/test/ezagent/uri/scheme_registry_test.exs` — new
- `apps/ezagent_core/test/ezagent/uri_test.exs` — update parse!/1 tests to use SchemeRegistry

## Verification

- `mix test` all 12 apps pass
- `Ezagent.URI.SchemeRegistry.list_all()` returns the SPEC §5.6 set at boot
- `parse!/1` rejects `parse!("madeup://x")` with clear error
- Strict mode rejection tested

## Scope

DO: ETS scheme registry. Update parse!/1. Co-register from SpawnRegistry.
DO NOT: Touch query-string action syntax (PR #146). Don't change AgentTypeRegistry yet (#147).

## Estimated effort

Small + focused. Subagent ~30-45 min.
