defmodule EzagentCli.Formatter do
  @moduledoc """
  Result → `{output_string, exit_code}`.

  Post-Phase-5 (Allen 2026-05-17): pure-data return. No IO side-effects.
  The CLI shell wrapper (Mix.Tasks.Esr) prints the output; the server-side
  HTTP controller returns it in the JSON response.

  Exit code conventions:
  - 0 = success
  - 1 = generic error (`{:error, reason}` not otherwise classified)
  - 2 = invalid args
  - 3 = unauthorized
  - 4 = no such actor (instance not spawned)
  """

  @doc """
  Render a dispatch result to a `{output_string, exit_code}` tuple.
  """
  @spec render({:ok, term()} | {:error, term()}, boolean()) :: {String.t(), non_neg_integer()}
  def render(result, json?)

  def render({:ok, :ok}, _json?), do: {"ok\n", 0}

  def render({:ok, result}, true), do: {Jason.encode!(result, pretty: true) <> "\n", 0}

  def render({:ok, result}, false) when is_map(result) do
    body =
      result
      |> Enum.map_join("\n", fn {k, v} ->
        "#{k}:\n" <> format_value(v, "  ")
      end)

    {body <> "\n", 0}
  end

  def render({:ok, result}, false), do: {inspect(result, pretty: true) <> "\n", 0}

  def render({:error, :unauthorized}, _json?), do: {"error: unauthorized\n", 3}

  # Phase 9 PR-4 (SPEC v3 §5) — workspace isolation denial. Distinct
  # exit code (5) so CI / scripts can distinguish "missing cap" from
  # "wrong workspace" without parsing stderr (invariant 9).
  def render({:error, :cross_workspace_denied}, _json?),
    do:
      {"error: cross-workspace denied (caller workspace != target workspace; " <>
         "need cross-workspace cap)\n", 5}

  def render({:error, :no_such_actor}, _json?),
    do: {"error: no such actor (did you spawn the instance?)\n", 4}

  def render({:error, {:invalid_args, violations}}, _json?) do
    body = "error: invalid args:\n" <> Enum.map_join(violations, "\n", &("  - " <> inspect(&1)))
    {body <> "\n", 2}
  end

  def render({:error, :as_not_allowed}, _json?),
    do:
      {"error: --as <other> is gated; set EZAGENT_CLI_ALLOW_AS=1 to enable (dev only)\n", 1}

  def render({:error, {:missing_instance_arg, type_name}}, _json?),
    do: {"error: missing --#{type_name} arg\n", 2}

  def render({:error, {:no_such_facade, kt, op}}, _json?),
    do: {"error: no facade op #{op} registered for #{inspect(kt)}\n", 1}

  def render({:error, reason}, _json?), do: {"error: #{inspect(reason)}\n", 1}

  defp format_value(list, indent) when is_list(list),
    do: Enum.map_join(list, "\n", &(indent <> "- " <> render_value(&1)))

  defp format_value(%URI{} = u, indent), do: indent <> URI.to_string(u)

  defp format_value(%MapSet{} = ms, indent),
    do: Enum.map_join(MapSet.to_list(ms), "\n", &(indent <> "- " <> render_value(&1)))

  defp format_value(v, indent), do: indent <> render_value(v)

  defp render_value(%URI{} = u), do: URI.to_string(u)
  defp render_value(v) when is_binary(v), do: v
  defp render_value(v), do: inspect(v)

end
