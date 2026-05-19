defmodule EzagentCore.Repo.Migrations.PrD2UnifyCcAgentTemplateClass do
  @moduledoc """
  PR-D2 (Allen 2026-05-19) — unify cc.pty + cc.channel_instance into
  cc.agent. This migration rewrites every `workspaces.session_templates`
  entry whose `class` was `"cc.pty"` or `"cc.channel_instance"` to
  the new `"cc.agent"` class, and adds a `"mode"` field:

  - `class: "cc.pty"`           → `class: "cc.agent", mode: "local-pty"`
  - `class: "cc.channel_instance"` → `class: "cc.agent", mode: "remote-channel"`

  All other fields (agent_uri, cwd, etc.) survive untouched.

  ## Why both rewrites map cleanly

  - cc.pty had a `cwd` field → cc.agent local-pty mode requires `cwd`.
  - cc.channel_instance had only `agent_uri` → cc.agent remote-channel
    mode doesn't need cwd, and that mode is currently a placeholder
    (Template.instantiate returns :not_implemented per PR-D2 plan).
    Until the remote half is wired, these rows are essentially
    inert — but rewriting them now means when remote-channel ships,
    no further migration is needed.

  ## Idempotency

  Re-running this migration is a no-op for any workspace already
  using `class: "cc.agent"`. The map_from_template_class/1 guards
  ensure only legacy class strings produce a rewrite.
  """

  use Ecto.Migration
  import Ecto.Query, warn: false
  require Logger

  alias EzagentCore.Repo

  def up do
    rows =
      Repo.query!(
        "SELECT id, session_templates FROM workspaces WHERE session_templates IS NOT NULL"
      ).rows

    rewritten =
      Enum.reduce(rows, 0, fn [id, st_json_bin], acc ->
        st = parse_json(st_json_bin)
        new_st = Map.new(st, fn {tmpl_name, tmpl} -> {tmpl_name, rewrite_template(tmpl)} end)

        if new_st != st do
          Repo.query!(
            "UPDATE workspaces SET session_templates = ?, updated_at = ? WHERE id = ?",
            [Jason.encode!(new_st), DateTime.utc_now(), id]
          )

          Logger.info("PR-D2: rewrote workspace #{id} session_templates → cc.agent")
          acc + 1
        else
          acc
        end
      end)

    Logger.info("PR-D2 migration complete (#{rewritten} workspace(s) rewritten)")
  end

  def down do
    Logger.warning(
      "PR-D2 migration is not reversible — cc.pty + cc.channel_instance Template Classes " <>
        "have been removed from the codebase. Roll back the code first if you need the old shape."
    )

    :ok
  end

  defp rewrite_template(%{"class" => "cc.pty"} = tmpl) do
    tmpl
    |> Map.put("class", "cc.agent")
    |> Map.put_new("mode", "local-pty")
  end

  defp rewrite_template(%{"class" => "cc.channel_instance"} = tmpl) do
    tmpl
    |> Map.put("class", "cc.agent")
    |> Map.put_new("mode", "remote-channel")
  end

  defp rewrite_template(tmpl), do: tmpl

  defp parse_json(nil), do: %{}
  defp parse_json(""), do: %{}
  defp parse_json(bin) when is_binary(bin), do: Jason.decode!(bin)
  defp parse_json(map) when is_map(map), do: map
end
