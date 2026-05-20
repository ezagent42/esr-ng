defmodule Ezagent.Test.CapHelper do
  @moduledoc """
  Phase 9 PR-3 (SPEC v3 §4) — test helper for constructing
  `Ezagent.Capability` structs without re-specifying the boilerplate
  fields (`workspace_uri`, `granted_by`, `granted_at`).

  The struct gained `workspace_uri` as a required field
  (`@enforce_keys`); rather than rewrite every test cap site to
  hand-thread the new field, tests build caps via `cap/1`:

      import Ezagent.Test.CapHelper

      cap = cap(kind: :session, behavior: :any, instance: :any)
      # → %Capability{kind: :session, behavior: :any, instance: :any,
      #              workspace_uri: %URI{scheme: "workspace", host: "default"},
      #              granted_by: %URI{scheme: "entity", ...},
      #              granted_at: ~U[...]}

  Tests that need a specific workspace pass `workspace_uri:` explicitly:

      cap(kind: :session, behavior: :any, instance: :any,
          workspace_uri: URI.new!("workspace://team-alpha"))

  Compiled only in `:test` per `apps/ezagent_core/mix.exs`
  `elixirc_paths(:test)`. Available to every umbrella app via
  `import` once the parent test depends on `ezagent_core`.

  ## Why a helper instead of updating each test cap inline

  Per the spec: ~30+ cap construction sites between lib + tests. Lib
  sites get the explicit workspace dimension because they live in
  production code paths. Test sites get a default so the contract
  pin stays focused on the test's actual concern (kind / behavior /
  instance matching), not workspace plumbing.
  """

  alias Ezagent.Capability

  @default_workspace URI.new!("workspace://default")
  @default_granter URI.parse("entity://user/default/admin")
  @default_granted_at ~U[2026-05-21 00:00:00Z]

  @doc """
  Build a `%Ezagent.Capability{}` with sensible test defaults.

  Required key absent → defaults applied:
  - `workspace_uri` → `workspace://default`
  - `granted_by` → `entity://user/default/admin`
  - `granted_at` → `2026-05-21T00:00:00Z`

  Pass any subset of keys to override; remaining keys default to
  `:any` (for `kind` / `behavior` / `instance`).

  ## Examples

      cap(kind: :session, behavior: Ezagent.Behavior.Chat,
          instance: URI.new!("session://default/main"))

      cap(kind: :any, behavior: :any, instance: :any,
          workspace_uri: :any)  # cross-workspace cap (admin pattern)
  """
  @spec cap(keyword() | map()) :: Capability.t()
  def cap(opts) when is_list(opts) or is_map(opts) do
    defaults = %{
      kind: :any,
      behavior: :any,
      instance: :any,
      workspace_uri: @default_workspace,
      granted_by: @default_granter,
      granted_at: @default_granted_at
    }

    merged = Map.merge(defaults, Enum.into(opts, %{}))
    struct!(Capability, merged)
  end

  @doc """
  Build a `needed` map for `Ezagent.Capability.matches?/2` with test
  defaults — mirror of `cap/1` for the lookup side.

  Defaults:
  - `kind` → `:any` (so a kind-less needed accidentally matches
    nothing — explicit kind is the norm)
  - `workspace_uri` → `workspace://default`

  ## Examples

      needed(kind: :session, behavior: Ezagent.Behavior.Chat,
             instance: URI.new!("session://default/main"))
  """
  @spec needed(keyword() | map()) :: %{
          kind: atom(),
          behavior: module() | atom(),
          instance: URI.t(),
          workspace_uri: URI.t() | :any
        }
  def needed(opts) when is_list(opts) or is_map(opts) do
    defaults = %{
      kind: :any,
      behavior: :any,
      instance: :any,
      workspace_uri: @default_workspace
    }

    Map.merge(defaults, Enum.into(opts, %{}))
  end

  @doc "Default test workspace URI: `workspace://default`."
  @spec default_workspace_uri() :: URI.t()
  def default_workspace_uri, do: @default_workspace
end
