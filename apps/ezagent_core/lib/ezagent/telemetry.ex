defmodule Ezagent.Telemetry do
  @moduledoc """
  Telemetry event naming helpers.

  Convention `[:ezagent, area, verb]` (borrowed from old esr — SPEC borrow
  pattern #2). Centralised here so future grep + linter passes can
  enumerate every event ESR emits.

  ## Event catalogue (Phase 3d current)

  | Event                                  | Emitted by             | Measurements      | Metadata |
  |----------------------------------------|------------------------|-------------------|----------|
  | `[:ezagent, :invoke, :stop]`               | `Ezagent.Kind.Runtime`     | `duration_us`     | target, caller, action, behavior_name, behavior_module, kind_module |
  | `[:ezagent, :invoke, :error]`              | `Ezagent.Kind.Runtime`     | `duration_us`     | target, caller, reason |
  | `[:ezagent, :authz, :granted]`             | `Ezagent.Kind.Runtime`     | (empty)           | kind_module, action, target, caller, needed |
  | `[:ezagent, :authz, :denied]`              | `Ezagent.Kind.Runtime`     | (empty)           | kind_module, action, target, caller, needed |
  | `[:ezagent, :dispatch, :no_actor]`         | `Ezagent.Invocation`       | (empty)           | target |
  | `[:ezagent, :dlq, :write]`                 | `Ezagent.DLQ`              | (empty)           | reason, payload |
  | `[:ezagent, :chat, :reply_session_mismatch]` | `Ezagent.Behavior.Chat`  | (empty)           | ref, target_sessions, ref_actual_sessions, reason |
  | `[:ezagent, :chat, :reply_dispatch_failed]`  | `Ezagent.Behavior.Chat`  | (empty)           | agent, target_session, reason, message_uri |

  Phase 1-2 `:authz` event was `:stub_grant` (permissive stub). Phase 3d
  hard flip (P3-D6) replaces with real `:granted` / `:denied`. The
  `:stub_grant` atom no longer appears in code (enforced by
  `check_invariants` #9).
  """

  @doc "Catalogue of all current telemetry event names."
  def all_events do
    [
      [:ezagent, :invoke, :stop],
      [:ezagent, :invoke, :error],
      [:ezagent, :authz, :granted],
      [:ezagent, :authz, :denied],
      [:ezagent, :dispatch, :no_actor],
      [:ezagent, :dlq, :write],
      [:ezagent, :chat, :reply_session_mismatch],
      [:ezagent, :chat, :reply_dispatch_failed]
    ]
  end
end
