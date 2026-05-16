defmodule EsrCLI.Formatter do
  @moduledoc """
  Result → stdout + exit code (Spec 02 §2.G).

  Exit code conventions:
  - 0 = success
  - 1 = generic error (`{:error, reason}` not otherwise classified)
  - 2 = invalid args
  - 3 = unauthorized
  - 4 = no such actor (instance not spawned)
  """

  @doc """
  Render a dispatch result + exit. Returns the exit code (caller's
  `Mix.Task` should `System.halt(code)` or raise).
  """
  @spec render({:ok, term()} | {:error, term()}, boolean()) :: non_neg_integer()
  def render(result, json?)

  def render({:ok, :ok}, _json?) do
    IO.puts("ok")
    0
  end

  def render({:ok, result}, true) do
    IO.puts(Jason.encode!(result, pretty: true))
    0
  end

  def render({:ok, result}, false) when is_map(result) do
    result
    |> Enum.each(fn {k, v} ->
      IO.puts("#{k}:")
      print_value(v, "  ")
    end)

    0
  end

  def render({:ok, result}, false) do
    IO.puts(inspect(result, pretty: true))
    0
  end

  def render({:error, :unauthorized}, _json?) do
    IO.puts(:stderr, "error: unauthorized")
    3
  end

  def render({:error, :no_such_actor}, _json?) do
    IO.puts(:stderr, "error: no such actor (did you spawn the instance?)")
    4
  end

  def render({:error, {:invalid_args, violations}}, _json?) do
    IO.puts(:stderr, "error: invalid args:")

    Enum.each(violations, fn v ->
      IO.puts(:stderr, "  - #{inspect(v)}")
    end)

    2
  end

  def render({:error, :as_not_allowed}, _json?) do
    IO.puts(:stderr,
      "error: --as <other> is gated; set ESR_CLI_ALLOW_AS=1 to enable (dev only)"
    )

    1
  end

  def render({:error, {:missing_instance_arg, type_name}}, _json?) do
    IO.puts(:stderr, "error: missing --#{type_name} arg")
    2
  end

  def render({:error, {:no_such_facade, kt, op}}, _json?) do
    IO.puts(:stderr, "error: no facade op #{op} registered for #{inspect(kt)}")
    1
  end

  def render({:error, reason}, _json?) do
    IO.puts(:stderr, "error: #{inspect(reason)}")
    1
  end

  defp print_value(list, indent) when is_list(list) do
    Enum.each(list, fn v -> IO.puts("#{indent}- #{render_value(v)}") end)
  end

  defp print_value(%URI{} = u, indent), do: IO.puts("#{indent}#{URI.to_string(u)}")

  defp print_value(%MapSet{} = ms, indent),
    do: Enum.each(MapSet.to_list(ms), fn v -> IO.puts("#{indent}- #{render_value(v)}") end)

  defp print_value(v, indent), do: IO.puts("#{indent}#{render_value(v)}")

  defp render_value(%URI{} = u), do: URI.to_string(u)
  defp render_value(v) when is_binary(v), do: v
  defp render_value(v), do: inspect(v)
end
