defmodule Esr.Telemetry do
  @moduledoc """
  Telemetry event naming helpers.

  Convention `[:esr, area, verb]` (borrowed from old esr — SPEC borrow
  pattern #2). Centralised here so future grep + linter passes can
  enumerate every event ESR emits.

  ## Event catalogue (Phase 3d current)

  | Event                                  | Emitted by             | Measurements      | Metadata |
  |----------------------------------------|------------------------|-------------------|----------|
  | `[:esr, :invoke, :stop]`               | `Esr.Kind.Runtime`     | `duration_us`     | target, caller, action, behavior_name, behavior_module, kind_module |
  | `[:esr, :invoke, :error]`              | `Esr.Kind.Runtime`     | `duration_us`     | target, caller, reason |
  | `[:esr, :authz, :granted]`             | `Esr.Kind.Runtime`     | (empty)           | kind_module, action, target, caller, needed |
  | `[:esr, :authz, :denied]`              | `Esr.Kind.Runtime`     | (empty)           | kind_module, action, target, caller, needed |
  | `[:esr, :dispatch, :no_actor]`         | `Esr.Invocation`       | (empty)           | target |
  | `[:esr, :dlq, :write]`                 | `Esr.DLQ`              | (empty)           | reason, payload |
  | `[:esr, :chat, :reply_session_mismatch]` | `Esr.Behavior.Chat`  | (empty)           | ref, target_sessions, ref_actual_sessions, reason |

  Phase 1-2 `:authz` event was `:stub_grant` (permissive stub). Phase 3d
  hard flip (P3-D6) replaces with real `:granted` / `:denied`. The
  `:stub_grant` atom no longer appears in code (enforced by
  `check_invariants` #9).
  """

  @doc "Catalogue of all current telemetry event names."
  def all_events do
    [
      [:esr, :invoke, :stop],
      [:esr, :invoke, :error],
      [:esr, :authz, :granted],
      [:esr, :authz, :denied],
      [:esr, :dispatch, :no_actor],
      [:esr, :dlq, :write],
      [:esr, :chat, :reply_session_mismatch]
    ]
  end
end
