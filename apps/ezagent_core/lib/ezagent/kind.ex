defmodule Ezagent.Kind do
  @moduledoc """
  Kind — contract for a Kind type module.

  Per DECISIONS P1-D2 / Decision #84: Phase 1 uses the
  `@behaviour Ezagent.Kind` + shared `Ezagent.Kind.Server` approach (path B
  in ARCHITECTURE.md §5.7.4), **not** a `use Ezagent.Kind` macro. The
  Kind module is a pure data declaration: which Behaviors it has,
  what its persistence policy is, etc. The `Ezagent.Kind.Server`
  GenServer instantiates one process per `{kind_module, args}` and
  delegates lifecycle (register → subscribe → announce_ready) so
  plugin authors cannot bypass it.

  ## Required callbacks

  - `type_name/0`: stable type atom (e.g. `:echo`, `:user`, `:agent`).
    Stored in snapshots — used to rehydrate, so renaming the module
    must not require a migration. Per Decision #62.
  - `behaviors/0`: list of `Ezagent.Behavior` modules this Kind composes.
  - `persistence/0`: snapshot strategy.

  ## Optional callbacks

  - `uri_from_args/1`: build the URI from instance args. Default
    implementation expects `args[:uri]` to be set by the caller.
  """

  @type persistence_policy ::
          :ephemeral
          | {:snapshot, :on_change}
          | {:snapshot, :periodic, ms :: pos_integer()}
          | :on_terminate
          | :external

  @callback type_name() :: atom()
  @callback behaviors() :: [module()]
  @callback persistence() :: persistence_policy()
  @callback uri_from_args(args :: map()) :: URI.t()
  @callback snapshot_version() :: non_neg_integer()

  @optional_callbacks [uri_from_args: 1, snapshot_version: 0]
end
