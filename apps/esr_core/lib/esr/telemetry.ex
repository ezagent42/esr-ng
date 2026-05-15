defmodule Esr.Telemetry do
  @moduledoc """
  Telemetry event naming helpers.

  Convention `[:esr, area, verb]` (borrowed from old esr — SPEC borrow
  pattern #2). Centralised here so future grep + linter passes can
  enumerate every event ESR emits.

  ## Phase 1 event catalogue

  | Event                          | Emitted by             | Measurements      | Metadata |
  |--------------------------------|------------------------|-------------------|----------|
  | `[:esr, :invoke, :stop]`       | `Esr.Kind.Runtime`     | `duration_us`     | target, caller, action, behavior_name, behavior_module, kind_module |
  | `[:esr, :invoke, :error]`      | `Esr.Kind.Runtime`     | `duration_us`     | target, caller, reason |
  | `[:esr, :authz, :stub_grant]`  | `Esr.Kind.Runtime`     | (empty)           | kind_module, behavior_module, target, caller |
  | `[:esr, :dispatch, :no_actor]` | `Esr.Invocation`       | (empty)           | target |
  | `[:esr, :dlq, :write]`         | `Esr.DLQ`              | (empty)           | reason, payload |
  """

  @doc "Catalogue of all Phase 1 telemetry event names."
  def phase1_events do
    [
      [:esr, :invoke, :stop],
      [:esr, :invoke, :error],
      [:esr, :authz, :stub_grant],
      [:esr, :dispatch, :no_actor],
      [:esr, :dlq, :write]
    ]
  end
end
