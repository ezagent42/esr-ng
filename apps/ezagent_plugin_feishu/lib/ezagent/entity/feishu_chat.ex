defmodule Ezagent.Entity.FeishuChat do
  @moduledoc """
  Phase 5 Plan B (Allen 2026-05-17) — Feishu chat as a Receiver Kind.

  `feishu://oc_xxx` is a real Kind that implements the receive side of
  `Ezagent.Behavior.Chat`. When a session's Resolver fans a message out,
  if the routing rules include `feishu://oc_xxx` as a receiver, the
  message reaches this Kind via `Ezagent.Invocation.dispatch` (CapBAC +
  audit + everything Cooperative). The Kind's `:receive` action calls
  the lark API.

  This is the ARCH-aligned shape per §5.4.4 "adapter is the receiver
  Kind" and replaces the v1 PubSub-subscriber side-channel that PR 6
  drifted into.

  Per the new memory `feedback_plugin_external_integration_is_receiver_kind`,
  any future plugin that needs to send messages out of ESR (Slack,
  Discord, email, webhook, …) MUST follow this pattern.

  ## Persistence

  `:ephemeral` — chat_id is the URI itself, nothing to persist beyond
  the routing rule pointing at it (which lives in the routing_rules
  SQLite table).
  """

  @behaviour Ezagent.Kind

  @impl Ezagent.Kind
  def type_name, do: :feishu_chat

  @impl Ezagent.Kind
  def behaviors, do: [EzagentPluginFeishu.Behavior.FeishuReceive]

  @impl Ezagent.Kind
  def persistence, do: :ephemeral

  @impl Ezagent.Kind
  def uri_from_args(args), do: Map.fetch!(args, :uri)

  @doc "Build a feishu chat URI from a chat_id string (`oc_…`)."
  @spec uri_for(String.t()) :: URI.t()
  def uri_for(chat_id) when is_binary(chat_id) do
    URI.parse("feishu://" <> chat_id)
  end

  @doc "Pull the chat_id back out of a feishu:// URI."
  @spec chat_id_from_uri(URI.t()) :: String.t()
  def chat_id_from_uri(%URI{scheme: "feishu", host: host, path: nil}) when is_binary(host),
    do: host

  # URI.parse("feishu://oc_xxx") on some elixir versions puts the value
  # in `:authority`/`:host` rather than path; handle both shapes.
  def chat_id_from_uri(%URI{scheme: "feishu", authority: auth}) when is_binary(auth), do: auth
end
