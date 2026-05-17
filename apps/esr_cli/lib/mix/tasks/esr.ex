defmodule Mix.Tasks.Esr do
  @shortdoc "CLI shell — connects via distributed Erlang to the running ESR runtime"
  @moduledoc """
  Post-Phase-5 second pivot (Allen 2026-05-17): `mix esr` is a thin
  shell that connects to the running ESR runtime via distributed
  Erlang RPC. The actual `EsrCLI.Exec.exec/1` runs INSIDE the
  runtime BEAM — same process tree as LV, same KindRegistry,
  same Repo, same audit telemetry. Restores CLI ↔ LV runtime
  isomorphism without any HTTP serde indirection.

  ## Usage

      mix esr <kind> <action> [--<arg>=<val> ...]
      mix esr --help
      mix esr help <subcommand>

  ## Environment

      ESR_RUNTIME_NODE   Node name to reach (default esr_runtime@127.0.0.1)
      ESR_HOME           Where the runtime cookie file lives
                         (default ~/.esr-ng)

  ## Single-machine assumption

  Per Allen's directive: CLI only ever talks to a LOCAL runtime. For
  remote operations, runtime-to-runtime federation (Roadmap §6+) handles
  the cross-machine case; CLI itself stays single-machine.

  If the runtime isn't running, prints a clear error.
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    case Esr.Runtime.connect_as_cli() do
      {:ok, runtime_node} ->
        case :rpc.call(runtime_node, EsrCLI.Exec, :exec, [argv], 30_000) do
          %{output: output, exit_code: code} ->
            IO.write(output)
            exit_with(code)

          {:badrpc, reason} ->
            IO.puts(:stderr, "error: rpc failed: #{inspect(reason)}")
            exit_with(1)
        end

      {:error, :runtime_not_reachable} ->
        IO.puts(:stderr,
          "error: ESR runtime not reachable at #{Esr.Runtime.runtime_node()}\n" <>
            "       start it with `mix phx.server` (single-machine assumption)\n" <>
            "       or set ESR_RUNTIME_NODE to point at a running instance"
        )

        exit_with(5)

      {:error, reason} ->
        IO.puts(:stderr, "error: #{inspect(reason)}")
        exit_with(1)
    end
  end

  defp exit_with(code) when is_integer(code) do
    if Mix.env() == :test do
      throw({:cli_exit, code})
    else
      System.halt(code)
    end
  end
end
