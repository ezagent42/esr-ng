defmodule EzagentCore.Repo.Migrations.Pr131AgentUriTypeSegment do
  @moduledoc """
  PR #131 (Allen 2026-05-19) — agent URIs now embed the type segment
  via `agent://<type>/<name>`. This migration rewrites existing rows
  so the demo workspace + routing rules continue working without
  manual operator intervention.

  ## What's rewritten

  - `workspaces.session_templates` JSON: for each entry
    - `class: "cc.pty"` → rewrite `agent_uri` to `agent://cc/<name>`
    - `class: "cc.channel_instance"` → same (cc type)
    - `class: "curl.agent"` → `agent://curl/<name>` (also handles
      legacy `curl-entity://agent/test_X` scheme)
  - `routing_rules.receivers` (JSON array of strings) — rewrite
    every URI based on the registered agent_uri ↔ class mapping
    derived from workspaces above

  ## What's NOT rewritten

  - `kind_snapshots.uri` rows for old agents — these regenerate
    naturally on the next workspace load (Template.instantiate will
    spawn the Kind at the new URI; the old snapshot row is
    orphaned). Orphan cleanup is a separate concern; non-load-bearing.

  ## Rollback

  Irreversible by design (the new agent registry only accepts the
  new shape). `down/0` is a no-op + warning.
  """

  use Ecto.Migration
  import Ecto.Query, warn: false
  require Logger

  alias EzagentCore.Repo

  def up do
    # Build the old-URI → new-URI rewrite map first by walking workspaces.
    rewrite_map = build_rewrite_map_from_workspaces()
    Logger.info("PR131 migration: #{map_size(rewrite_map)} URIs need rewriting")

    rewrite_workspace_templates(rewrite_map)
    rewrite_routing_rules(rewrite_map)

    Logger.info("PR131 migration complete")
  end

  def down do
    Logger.warning(
      "PR131 migration is not reversible — the new agent registry rejects un-typed URIs. " <>
        "If you need to roll back, manually edit workspaces + routing_rules to remove the type segments."
    )

    :ok
  end

  defp build_rewrite_map_from_workspaces do
    rows =
      Repo.query!(
        "SELECT id, session_templates FROM workspaces WHERE session_templates IS NOT NULL"
      ).rows

    Enum.reduce(rows, %{}, fn [_id, st_json_bin], acc ->
      st = parse_json(st_json_bin)

      Enum.reduce(st, acc, fn {_tmpl_name, tmpl}, acc2 ->
        case rewrite_for_template(tmpl) do
          {old, new} when old != new -> Map.put(acc2, old, new)
          _ -> acc2
        end
      end)
    end)
  end

  defp rewrite_for_template(%{"class" => class, "agent_uri" => uri_str})
       when class in ["cc.pty", "cc.channel_instance"] do
    {uri_str, normalize_agent_uri(uri_str, "cc")}
  end

  defp rewrite_for_template(%{"class" => "curl.agent", "agent_uri" => uri_str}) do
    {uri_str, normalize_agent_uri(uri_str, "curl")}
  end

  defp rewrite_for_template(_), do: nil

  # Already has type segment → keep as-is. Otherwise prepend type.
  defp normalize_agent_uri("agent://" <> rest, type) do
    case URI.new("agent://" <> rest) do
      {:ok, %URI{host: host, path: nil}} ->
        # `entity://agent/test_just-a-name` → `agent://<type>/just-a-name`
        "agent://#{type}/#{host}"

      {:ok, %URI{host: existing_type, path: "/" <> _name}} ->
        # Already typed — keep as-is regardless of whether it matches.
        # (If it mismatches, the operator deliberately put a wrong type;
        # the validator will reject at workspace load.)
        "agent://" <> rest

      _ ->
        "agent://" <> rest
    end
  end

  # `curl-entity://agent/test_X` legacy scheme → `entity://agent/curl_X`
  defp normalize_agent_uri("curl-agent://" <> name, "curl"), do: "agent://curl/#{name}"

  defp normalize_agent_uri(other, _type), do: other

  defp rewrite_workspace_templates(rewrite_map) do
    rows =
      Repo.query!(
        "SELECT id, session_templates FROM workspaces WHERE session_templates IS NOT NULL"
      ).rows

    for [id, st_json_bin] <- rows do
      st = parse_json(st_json_bin)

      new_st =
        Map.new(st, fn {tmpl_name, tmpl} ->
          {tmpl_name, rewrite_template_map(tmpl, rewrite_map)}
        end)

      if new_st != st do
        new_json = Jason.encode!(new_st)

        Repo.query!(
          "UPDATE workspaces SET session_templates = ?, updated_at = ? WHERE id = ?",
          [new_json, DateTime.utc_now(), id]
        )

        Logger.info("PR131: rewrote workspace #{id} session_templates")
      end
    end
  end

  defp rewrite_template_map(%{"agent_uri" => old} = tmpl, rewrite_map) do
    case Map.get(rewrite_map, old) do
      nil -> tmpl
      new -> Map.put(tmpl, "agent_uri", new)
    end
  end

  defp rewrite_template_map(tmpl, _), do: tmpl

  defp rewrite_routing_rules(rewrite_map) do
    rows = Repo.query!("SELECT id, receivers FROM routing_rules").rows

    for [id, receivers_json_bin] <- rows do
      receivers =
        case parse_json(receivers_json_bin) do
          list when is_list(list) -> list
          _ -> []
        end

      new_receivers =
        Enum.map(receivers, fn r ->
          case Map.get(rewrite_map, r) do
            nil -> r
            new -> new
          end
        end)

      if new_receivers != receivers do
        Repo.query!("UPDATE routing_rules SET receivers = ? WHERE id = ?", [
          Jason.encode!(new_receivers),
          id
        ])

        Logger.info("PR131: rewrote routing_rules.id=#{id} receivers")
      end
    end
  end

  defp parse_json(nil), do: %{}
  defp parse_json(""), do: %{}
  defp parse_json(bin) when is_binary(bin), do: Jason.decode!(bin)
  defp parse_json(map) when is_map(map), do: map
  defp parse_json(list) when is_list(list), do: list
end
