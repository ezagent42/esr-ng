defmodule Mix.Tasks.Esr.CheckInvariants do
  @shortdoc "Check ESR's 8 hard invariants (Phase 0: skeleton, no-op)"

  @moduledoc """
  Greps the codebase for violations of ESR's 8 hard invariants
  (ARCHITECTURE.md Decision Log / CLAUDE.md §8 不变式).

  ## Phase 0 status: skeleton

  Phase 0 has no dispatch path, no Kind, no routing — so none of the 8
  invariants apply yet. This task is intentionally a near-no-op skeleton.

  Each subsequent phase's brainstorm extends `run/1` with the grep checks
  for invariants that become relevant once the corresponding code exists
  (e.g. Phase 1 adds #1 inbound-via-dispatch, #2 use-Esr.Kind lifecycle,
  #3 :call-to-not-ready fail-fast).

  Invoked by the sub-step gate (`scripts/hooks/sub-step-gate.sh`) and
  available standalone as `mix esr.check_invariants`.
  """
  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info(
      "esr.check_invariants — Phase 0: no invariants apply yet (no dispatch path exists)"
    )

    :ok
  end
end
