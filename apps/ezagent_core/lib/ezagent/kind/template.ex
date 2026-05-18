defmodule Ezagent.Kind.Template do
  @moduledoc """
  Template Class behaviour — the Class half of Decision #64's double
  Template model (Class + Instance).

  ## Position in the model

  - **Template Instance** (already shipped Phase 4b/c) — a Workspace
    Kind carrying `session_templates` map in state.
  - **Template Class** (this behaviour) — plugin-author module that
    knows how to validate template data and instantiate Kinds from it.

  A Workspace's `session_templates` entry references a Class by name
  (`"class"` field in the template data); `Ezagent.TemplateRegistry` maps
  name → module; `Ezagent.Workspace.Loader` dispatches `instantiate/3` at
  app start to bring the declared Kinds to life.

  This is the **runtime DI form** for plugin authors to add new
  spawnable shapes without touching ezagent_core — parallel to
  `Ezagent.SpawnRegistry` (one-Kind-per-URI-scheme) but for whole
  composable structures (Session + members + routing).

  ## Callbacks

  - `template_name/0` — stable string id (e.g. `"session.generic"`).
    Stored in the Workspace's `session_templates` map as the `"class"`
    field. Per Decision #62 (snapshot-safe stable IDs).
  - `validate/1` — pure shape check called by
    `Ezagent.Workspace.add_template/3` BEFORE persisting. Fail-fast.
    Optional callback — default `:ok`.
  - `instantiate/3` — effectful. Called by `Ezagent.Workspace.Loader` at
    boot and by `add_template/3` after persist. **Must be idempotent**:
    re-calling after the spawned Kinds are alive should be a no-op,
    returning the same URIs (`SpawnRegistry.spawn/1` provides this for
    the common case).

  ## Return shape of `instantiate/3`

  `{:ok, [URI.t()]}` — list of URIs the Class spawned. Loader records
  these for telemetry / observability. Returning a list (not a single
  URI) lets a Class spawn multiple Kinds in one call (e.g. Session +
  N Agents + connections).
  """

  @type template_data :: map()
  @type template_name :: String.t()

  @callback template_name() :: template_name()
  @callback validate(template_data()) :: :ok | {:error, term()}
  @callback instantiate(template_name(), template_data(), workspace_uri :: URI.t()) ::
              {:ok, [URI.t()]} | {:error, term()}

  @optional_callbacks [validate: 1]
end
