defmodule Mix.Tasks.Esr do
  @shortdoc "Thin CLI shell over running ESR server (POSTs argv to /api/cli/exec)"
  @moduledoc """
  Post-Phase-5 pivot (Allen 2026-05-17): this task is a **thin shell
  over the running server**. It does NOT boot ESR locally; instead it
  POSTs `{argv: [...]}` to `<server>/api/cli/exec`, prints the response,
  exits with the server-reported exit code.

  This restores CLI ↔ LV runtime isomorphism: both CLI invocations
  and LV form-submits execute inside the same BEAM that runs phx.server,
  hit the same KindRegistry, write to the same Repo, fire the same
  audit telemetry.

  ## Usage

      mix esr <kind> <action> [--<arg>=<val> ...]
      mix esr --help
      mix esr help <subcommand>

  ## Environment

      ESR_SERVER_URL    base URL of running server (default http://localhost:4000)

  ## What if the server isn't running?

  Prints a clear error + exit 5. Start phx.server then re-run.
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)

    server_url = System.get_env("ESR_SERVER_URL") || "http://localhost:4000"

    case post_exec(server_url, argv) do
      {:ok, %{"output" => output, "exit_code" => code}} ->
        IO.write(output)
        exit_with(code)

      {:error, :server_not_running} ->
        IO.puts(:stderr,
          "error: ESR server not running at #{server_url}\n" <>
            "       start it with: cd " <>
            File.cwd!() <> " && mix phx.server\n" <>
            "       or set ESR_SERVER_URL to point at the running instance"
        )

        exit_with(5)

      {:error, reason} ->
        IO.puts(:stderr, "error: #{inspect(reason)}")
        exit_with(1)
    end
  end

  defp post_exec(server_url, argv) do
    body = Jason.encode!(%{argv: argv})

    request =
      {String.to_charlist(server_url <> "/api/cli/exec"),
       [{~c"Content-Type", ~c"application/json"}], ~c"application/json", body}

    case :httpc.request(:post, request,
           [{:timeout, 30_000}, {:connect_timeout, 2_000}],
           []
         ) do
      {:ok, {{_, 200, _}, _, resp}} ->
        Jason.decode(to_string(resp))

      {:ok, {{_, status, _}, _, resp}} ->
        {:error, {:http_status, status, to_string(resp)}}

      {:error, {:failed_connect, _}} ->
        {:error, :server_not_running}

      {:error, reason} ->
        {:error, {:http_error, reason}}
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
