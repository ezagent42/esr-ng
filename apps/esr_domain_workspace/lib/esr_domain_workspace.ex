defmodule EsrDomainWorkspace do
  @moduledoc """
  Workspace domain — declarative `workspace://<name>` Kinds that hold
  Sessions + their members across restarts.

  Public surface:
  - `Esr.Workspace` — facade for CRUD + dispatch
  - `Esr.Workspace.Loader` — boot-time re-spawn
  - `Esr.Workspace.Store` — Ecto schema
  - `Esr.Entity.Workspace` — Kind
  - `Esr.Behavior.Workspace` — Behavior

  Phase 6 PR 2: extracted from esr_core. See SPEC.
  """
end
