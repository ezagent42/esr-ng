defmodule EsrPluginFeishu.MentionParser do
  @moduledoc """
  Phase 6 PR 16 — text-grep based @mention extraction (B2 route per
  Allen 2026-05-17).

  ## Why text-grep not lark mentioned_users

  lark's `mentioned_users` field carries Feishu open_ids — the user
  would need to type a real Feishu user's name (and that user would
  need to exist in the chat). To target an ESR agent (which has no
  Feishu identity), we use the simpler convention:

      @<agent-name>  →  agent://<agent-name>

  ESR is the source of truth for agent URIs, and the chat is just a
  human-readable surface. If you have an `agent://cc-architect` live
  and someone types `@cc-architect 看看`, the message routes only
  to that agent via MentionRouting (the existing matcher).

  ## Resolution

  Each `@<name>` token is checked against `Esr.KindRegistry` for
  a live `agent://<name>`. Unknown names are ignored (no Message
  mention added — admin sees the message in /admin but no agent
  gets singled out).

  Allen 2026-05-17: "B2 路线可以，暂时只考虑文字" — text only,
  no attachment-level mentions.
  """

  alias Esr.KindRegistry

  @mention_re ~r/@([A-Za-z0-9_\-\.]+)/

  @doc """
  Extract live agent URIs from free text. Returns `[URI.t()]`.

      iex> EsrPluginFeishu.MentionParser.extract_agent_mentions("@cc-architect look")
      [%URI{scheme: "agent", host: "cc-architect", ...}]   # if live

  Returns `[]` if no `@name` tokens or none of them resolve.
  """
  @spec extract_agent_mentions(String.t()) :: [URI.t()]
  def extract_agent_mentions(text) when is_binary(text) do
    @mention_re
    |> Regex.scan(text, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.flat_map(&candidate_uris/1)
    |> Enum.filter(&live?/1)
    |> Enum.uniq_by(&URI.to_string/1)
  end

  def extract_agent_mentions(_), do: []

  # Each `@name` token expands to candidate URIs. For now only
  # `agent://<name>` is considered — Phase 7 can add `session://`
  # and `user://` if needed.
  defp candidate_uris(name) do
    [URI.parse("agent://" <> name)]
  end

  defp live?(%URI{} = uri) do
    case KindRegistry.lookup(uri) do
      {:ok, _pid} -> true
      :error -> false
    end
  end
end
