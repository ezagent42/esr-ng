defmodule Mix.Tasks.Esr.CheckInvariants do
  @shortdoc "Check ESR's 8 hard invariants — Phase 1 step-3 active"

  @moduledoc """
  Greps the codebase for violations of ESR's 8 hard invariants
  (ARCHITECTURE.md Decision Log / GLOSSARY.md / VERIFICATION.md
  §不变式 grep 完整命令清单).

  ## Progressive coverage

  Each Phase 1 step extends this task with the invariants that become
  meaningfully checkable once the relevant code lands:

  - **Phase 0**: no-op (no dispatch path)
  - Step 1: invariant **#4 put_new for unique-key**
  - Step 2: adds **#2** (use Esr.Kind lifecycle) and **#3**
    (`:not_ready + :call` fail-fast)
  - **Step 3** (this commit): adds **#1** (inbound via dispatch —
    `PubSub.broadcast` allowlist: only `:events` topics and
    `esr:audit:stream` may broadcast), **#6** (audit async — no
    direct SQL in `audit.ex`), and **#7** (zero-match → DLQ)
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
    Mix.shell().info("esr.check_invariants — Phase 1 step 3 active")

    failures =
      [
        check_invariant_1(),
        check_invariant_2(),
        check_invariant_3(),
        check_invariant_4(),
        check_invariant_6(),
        check_invariant_7()
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

  # Invariant #1: inbound via dispatch (no bare PubSub.broadcast)
  # `Phoenix.PubSub.broadcast` is legitimate for:
  # - `:events` topics (view fan-out per §5.7.6)
  # - `esr:audit:stream` (audit view fan-out, this is `Esr.Audit`)
  # Any other broadcast call would be an inbound-message path which
  # MUST go through `Esr.Invocation.dispatch/1` instead (event 2.1
  # root cause).
  defp check_invariant_1 do
    # Allowlisted files for PubSub.broadcast:
    # - `audit.ex`: legitimate view fan-out to esr:audit:stream (§5.7.6)
    # - `invocation.ex`: reply path :phoenix_pubsub (caller chose this
    #   reply target explicitly — not an inbound message broadcast)
    # Plus the standard exclusions (tests, this checker).
    {output, _exit_code} =
      System.cmd(
        "bash",
        [
          "-c",
          # Strip lines that are pure prose mentions (backtick-quoted
          # symbol inside docstring) rather than actual code calls.
          "grep -rnE 'PubSub\\.broadcast' apps/esr_core apps/esr_plugin_echo apps/esr_web_liveview 2>/dev/null --include='*.ex' " <>
            "| grep -v 'lib/esr/audit.ex' " <>
            "| grep -v 'lib/esr/invocation.ex' " <>
            "| grep -v '_test.exs' " <>
            "| grep -v 'esr.check_invariants.ex' " <>
            "| grep -v ' `PubSub' || true"
        ],
        stderr_to_stdout: true
      )

    if String.trim(output) == "" do
      Mix.shell().info("  ✓ #1 inbound via dispatch (no bare PubSub.broadcast)")
      :ok
    else
      {:error, 1, output}
    end
  end

  # Invariant #2: use Esr.Kind lifecycle
  # Per Decision #84: only `Esr.Kind.Server` should define `def init/1`.
  # Plugin Kind modules (Echo, User, etc.) declare `@behaviour Esr.Kind`
  # and rely on the shared server — they must not write their own init.
  defp check_invariant_2 do
    {output, _exit_code} =
      System.cmd(
        "bash",
        [
          "-c",
          "grep -rnE '^\\s*def init\\(' apps/esr_core apps/esr_plugin_echo apps/esr_web_liveview 2>/dev/null --include='*.ex' " <>
            "| grep -v 'kind/server.ex' " <>
            "| grep -v 'ets_owner.ex' " <>
            "| grep -v 'idempotency/sweeper.ex' " <>
            "| grep -v 'audit/writer.ex' " <>
            "| grep -v 'esr_core/application.ex' " <>
            "| grep -v 'esr_plugin_echo/application.ex' " <>
            "| grep -v '_test.exs' || true"
        ],
        stderr_to_stdout: true
      )

    if String.trim(output) == "" do
      Mix.shell().info("  ✓ #2 use Esr.Kind lifecycle (only Kind.Server has def init)")
      :ok
    else
      {:error, 2, output}
    end
  end

  # Invariant #3: :call to not-ready fail-fast
  # `Esr.Invocation.dispatch/1` must have a clause matching
  # `{:not_ready, mode}` when mode is `:call` or `:call_stream`, so that
  # synchronous callers don't block until deadline_ms.
  defp check_invariant_3 do
    {output, _exit_code} =
      System.cmd(
        "bash",
        [
          "-c",
          "grep -E ':not_ready, m\\} when m in \\[:call' " <>
            "apps/esr_core/lib/esr/invocation.ex || true"
        ],
        stderr_to_stdout: true
      )

    if String.trim(output) == "" do
      {:error, 3, "missing fail-fast clause in invocation.ex for {:not_ready, :call}"}
    else
      Mix.shell().info("  ✓ #3 :call to not-ready fail-fast (clause present)")
      :ok
    end
  end

  # Invariant #6: audit handler async-only
  # `apps/esr_core/lib/esr/audit.ex` must not write SQLite directly —
  # it should only `:telemetry`-emit, `PubSub.broadcast`, and
  # `GenServer.cast` to `Esr.Audit.Writer`. The SQL write lives in
  # `audit/writer.ex` per Decision #60.
  defp check_invariant_6 do
    # Look for actual code calls to Repo.insert/update/delete or exqlite
    # — skip lines that are entirely comments / docstrings (start with #
    # or ` after trimming, or contain the symbol inside backticks).
    {output, _exit_code} =
      System.cmd(
        "bash",
        [
          "-c",
          "grep -nE 'EsrCore\\.Repo\\.(insert|update|delete)|exqlite' " <>
            "apps/esr_core/lib/esr/audit.ex " <>
            "| grep -v '^[[:space:]]*#' " <>
            "| grep -v ' `Esr\\.Repo' " <>
            "| grep -v 'Repo\\.insert.*in `audit\\.ex' || true"
        ],
        stderr_to_stdout: true
      )

    if String.trim(output) == "" do
      Mix.shell().info("  ✓ #6 audit handler async (no direct Repo writes)")
      :ok
    else
      {:error, 6, output}
    end
  end

  # Invariant #7: zero-match → DLQ unroutable
  # `Esr.DLQ.put/2` must accept `:unroutable` (zero-match routing
  # outcome — invariant #68 / §5.5.5 / Phase 2 chat routing). The
  # actual zero-match callsite arrives with RoutingRegistry in Phase 2;
  # Phase 1 verifies the API contract exists for use.
  defp check_invariant_7 do
    {output, _exit_code} =
      System.cmd(
        "bash",
        [
          "-c",
          "grep -E ':unroutable' apps/esr_core/lib/esr/dlq.ex || true"
        ],
        stderr_to_stdout: true
      )

    if String.trim(output) == "" do
      {:error, 7, "Esr.DLQ does not declare :unroutable reason"}
    else
      Mix.shell().info("  ✓ #7 zero-match → DLQ :unroutable (API present)")
      :ok
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
