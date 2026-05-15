defmodule Mix.Tasks.Esr.CheckInvariants do
  @shortdoc "Check ESR's 8 hard invariants — Phase 1 step-1 active"

  @moduledoc """
  Greps the codebase for violations of ESR's 8 hard invariants
  (ARCHITECTURE.md Decision Log / GLOSSARY.md / VERIFICATION.md
  §不变式 grep 完整命令清单).

  ## Progressive coverage

  Each Phase 1 step extends this task with the invariants that become
  meaningfully checkable once the relevant code lands:

  - **Phase 0**: no-op (no dispatch path)
  - **Step 1** (this commit): invariant **#4 put_new for unique-key** —
    `Esr.KindRegistry` exists, so we can grep for bare
    `Registry.register` outside the `put_new` wrapper
  - Step 2 will add **#2** (use Esr.Kind lifecycle, only `kind/server.ex`
    has `def init`) and **#3** (`:not_ready + :call` fail-fast)
  - Step 3 will add **#1** (inbound via dispatch — `PubSub.broadcast`
    allowlist), **#6** (audit async), and **#7** (zero-match → DLQ)
  - Phase 2+ will add **#5** (snapshot on slice change) and **#8**
    (CC channel via stdio)

  ## Exit semantics

  Exit `0` = all in-scope invariants pass.
  Exit non-zero = at least one violation; stderr contains the failing
  grep output and the invariant number.

  Invoked by the sub-step gate (`scripts/hooks/sub-step-gate.sh`) and
  available standalone as `mix esr.check_invariants`.
  """
  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info("esr.check_invariants — Phase 1 step 1 active")

    failures =
      [
        check_invariant_4()
      ]
      |> Enum.reject(&match?(:ok, &1))

    if failures == [] do
      Mix.shell().info("  ✓ all in-scope invariants clean")
      :ok
    else
      Enum.each(failures, fn {:error, num, output} ->
        Mix.shell().error("  ✗ invariant ##{num} VIOLATION:")
        Mix.shell().error(output)
      end)

      Mix.raise("esr.check_invariants: #{length(failures)} invariant(s) violated")
    end
  end

  # Invariant #4: put_new for unique-key
  # Bare `Registry.register` (without going through KindRegistry.put_new)
  # would silently overwrite a prior live instance. Only allow it inside
  # the `put_new` wrapper in `kind_registry.ex` and tests (which set up
  # fixtures directly).
  defp check_invariant_4 do
    # Exclude:
    # - `kind_registry.ex`: the legitimate caller (wrapped in put_new)
    # - `_test.exs`: tests may use Registry directly for fixtures
    # - `esr.check_invariants.ex`: this file itself mentions the symbol
    #   in docstrings and the grep command literal
    {output, _exit_code} =
      System.cmd(
        "bash",
        [
          "-c",
          "grep -rn 'Registry.register' apps/esr_core --include='*.ex' " <>
            "| grep -v 'kind_registry.ex' " <>
            "| grep -v '_test.exs' " <>
            "| grep -v 'esr.check_invariants.ex' || true"
        ],
        stderr_to_stdout: true
      )

    if String.trim(output) == "" do
      Mix.shell().info("  ✓ #4 put_new for unique-key (no bare Registry.register)")
      :ok
    else
      {:error, 4, output}
    end
  end
end
