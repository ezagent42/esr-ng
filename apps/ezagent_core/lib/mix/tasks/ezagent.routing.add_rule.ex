defmodule Mix.Tasks.Ezagent.Routing.AddRule do
  @shortdoc "Add a routing rule to a RoutingRegistry table"
  @moduledoc """
  Phase 3 admin tool to add a routing rule from the CLI.

  ## Usage

      mix ezagent.routing.add_rule <TableName> <matcher_spec> receivers:<uri1>,<uri2>

  ### Matcher specs

  - `mention:<uri>` — `Ezagent.Routing.Matcher.mention(uri)`
  - `from:<uri>`
  - `text_contains:<substring>`
  - `text_matches:<regex>`
  - `always` (no arg)

  ### Examples

      # text_contains rule: any urgent message → oncall session
      mix ezagent.routing.add_rule EzagentDomainChat.Routing.MentionRouting \\
          text_contains:urgent receivers:session://default/oncall

      # mention rule: @cc_builder → architect session
      mix ezagent.routing.add_rule EzagentDomainChat.Routing.MentionRouting \\
          mention:entity://agent/default/cc_builder receivers:session://default/architect

  ## Behavior

  1. Parses matcher_spec → `Ezagent.Routing.Matcher.matcher_tuple`
  2. Parses receivers → `[URI.t()]`
  3. Persists via `Ezagent.Routing.RuleStore.add/4`(created_by = nil for
     CLI; LV form will pass admin URI)
  4. Reloads the live `RoutingRegistry` table so the rule is in effect
     immediately (no restart needed)

  Phase 4 will add `mix ezagent.routing.list` / `mix ezagent.routing.delete`.
  """
  use Mix.Task

  alias Ezagent.Routing.{Matcher, RuleStore}

  @impl Mix.Task
  def run(args) do
    {:ok, _} = Application.ensure_all_started(:ezagent_domain_chat)

    case args do
      [table_str, matcher_spec, "receivers:" <> receivers_csv] ->
        with {:ok, table} <- parse_table(table_str),
             {:ok, matcher} <- parse_matcher(matcher_spec),
             receivers <- parse_receivers(receivers_csv),
             {:ok, row} <- RuleStore.add(table, matcher, receivers, nil),
             :ok <- RuleStore.load_into_registry(table) do
          Mix.shell().info(
            "added rule id=#{row.id} to #{table_str}: #{inspect(matcher)} → #{inspect(receivers)}"
          )
        else
          {:error, reason} -> Mix.raise("failed: #{inspect(reason)}")
        end

      _ ->
        Mix.raise("""
        usage: mix ezagent.routing.add_rule <TableName> <matcher_spec> receivers:<uri1>,<uri2>

        matcher_spec ::= mention:<uri> | from:<uri> | text_contains:<str> |
                         text_matches:<regex> | always
        """)
    end
  end

  defp parse_table(s) when is_binary(s) do
    try do
      {:ok, String.to_existing_atom("Elixir." <> s)}
    rescue
      ArgumentError -> {:error, {:unknown_table, s}}
    end
  end

  defp parse_matcher("always"), do: {:ok, Matcher.always()}
  defp parse_matcher("mention:" <> uri), do: {:ok, Matcher.mention(uri)}
  defp parse_matcher("from:" <> uri), do: {:ok, Matcher.from(uri)}
  defp parse_matcher("text_contains:" <> s), do: {:ok, Matcher.text_contains(s)}

  defp parse_matcher("text_matches:" <> re) do
    try do
      {:ok, Matcher.text_matches(re)}
    rescue
      _ -> {:error, {:bad_regex, re}}
    end
  end

  defp parse_matcher(other), do: {:error, {:unknown_matcher, other}}

  defp parse_receivers(csv), do: String.split(csv, ",", trim: true)
end
