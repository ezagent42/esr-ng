defmodule EzagentCore.Repo.Migrations.PrD1RewriteLegacyUrisInMatcherData do
  @moduledoc """
  PR-D1 (Allen 2026-05-19) — follow-up to PR #131 (agent URI type
  segment). PR #131's migration only rewrote `workspaces.session_templates`
  and `routing_rules.receivers`. It missed `routing_rules.matcher_data`,
  which embeds URIs inside JSON matcher trees (e.g. `{"type": "mention",
  "arg": "entity://agent/test_demo-builder"}`). Result: rules created before
  PR #131 against the legacy un-typed URI silently stopped matching.

  ## What this fixes

  - Walks every `routing_rules.matcher_data` JSON tree (including
    nested `and`/`or` combinators) and rewrites any `"arg"` string
    that looks like a legacy `agent://<name>` (no type segment) or
    `curl-agent://<name>` to the typed PR #131 form.
  - The rewrite map is derived the SAME way PR #131's migration does:
    walk every `workspaces.session_templates` entry, map its declared
    `agent_uri` (possibly already rewritten by PR #131) to its
    `class` (cc.pty/cc.channel_instance → "cc"; curl.agent → "curl").
    The reverse map (`legacy → typed`) then drives the matcher rewrite.

  ## What this does NOT touch

  - `messages.sender` / `messages.mentions` (historical audit data —
    a 2026-05-18 message saying `entity://agent/test_demo-builder` SAID that, full
    stop; rewriting it would falsify history).
  - `kind_snapshots` orphan rows from old un-typed agent URIs. These
    take disk space but don't break anything; the live agent is at
    the new typed URI and writes its own snapshot row. A separate
    cleanup pass would garbage-collect them; not load-bearing here.
  """

  use Ecto.Migration
  import Ecto.Query, warn: false
  require Logger

  alias EzagentCore.Repo

  def up do
    rewrite_map = build_rewrite_map()

    if map_size(rewrite_map) == 0 do
      Logger.info("PR-D1: no agents found in workspaces — skipping matcher_data rewrite")
    else
      Logger.info(
        "PR-D1: rewriting matcher_data with #{map_size(rewrite_map)} legacy → typed mappings"
      )

      Enum.each(rewrite_map, fn {old, new} -> Logger.info("PR-D1:   #{old} → #{new}") end)

      rewrite_matcher_data(rewrite_map)
    end

    Logger.info("PR-D1 migration complete")
  end

  def down do
    Logger.warning("PR-D1 is not reversible — same rationale as PR #131 migration.")
    :ok
  end

  # Build {legacy_uri_string → typed_uri_string} by inspecting workspaces.
  defp build_rewrite_map do
    rows =
      Repo.query!("SELECT session_templates FROM workspaces WHERE session_templates IS NOT NULL").rows

    Enum.reduce(rows, %{}, fn [st_json_bin], acc ->
      st = parse_json(st_json_bin)

      Enum.reduce(st, acc, fn {_tmpl_name, tmpl}, acc2 ->
        case legacy_to_typed(tmpl) do
          nil -> acc2
          {legacy, typed} when legacy == typed -> acc2
          {legacy, typed} -> Map.put(acc2, legacy, typed)
        end
      end)
    end)
  end

  # For each template, derive (legacy_form, typed_form) for the agent URI.
  defp legacy_to_typed(%{"class" => class, "agent_uri" => typed_uri})
       when class in ["cc.pty", "cc.channel_instance"] do
    {legacy_form(typed_uri, "cc"), typed_uri}
  end

  defp legacy_to_typed(%{"class" => "curl.agent", "agent_uri" => typed_uri}) do
    {legacy_form(typed_uri, "curl"), typed_uri}
  end

  defp legacy_to_typed(_), do: nil

  # `entity://agent/cc_X` → legacy `entity://agent/test_X` (the form PR-pre-#131 stored)
  # `entity://agent/curl_X` → legacy `entity://agent/test_X` (the form an admin would have typed)
  # Also: anything else → returns as-is (no rewrite produced).
  defp legacy_form("agent://" <> rest, _type) do
    case String.split(rest, "/", parts: 2) do
      [_type_only, name] -> "agent://#{name}"
      [other] -> "agent://#{other}"
    end
  end

  defp legacy_form(other, _), do: other

  defp rewrite_matcher_data(rewrite_map) do
    rows = Repo.query!("SELECT id, matcher_data FROM routing_rules").rows

    for [id, matcher_json_bin] <- rows do
      matcher = parse_json(matcher_json_bin)
      new_matcher = rewrite_matcher(matcher, rewrite_map)

      if new_matcher != matcher do
        Repo.query!("UPDATE routing_rules SET matcher_data = ? WHERE id = ?", [
          Jason.encode!(new_matcher),
          id
        ])

        Logger.info("PR-D1: rewrote routing_rules.id=#{id} matcher_data")
      end
    end
  end

  # Recurse into the matcher tree. Combinators carry `items: [...]` of
  # sub-matchers; leaf matchers carry `arg: "<uri>"` (mention / from) or
  # have no arg (always).
  defp rewrite_matcher(%{"items" => items} = matcher, rewrite_map) when is_list(items) do
    Map.put(matcher, "items", Enum.map(items, &rewrite_matcher(&1, rewrite_map)))
  end

  defp rewrite_matcher(%{"arg" => arg} = matcher, rewrite_map) when is_binary(arg) do
    case Map.get(rewrite_map, arg) do
      nil -> matcher
      new -> Map.put(matcher, "arg", new)
    end
  end

  defp rewrite_matcher(other, _), do: other

  defp parse_json(nil), do: %{}
  defp parse_json(""), do: %{}
  defp parse_json(bin) when is_binary(bin), do: Jason.decode!(bin)
  defp parse_json(map) when is_map(map), do: map
  defp parse_json(list) when is_list(list), do: list
end
