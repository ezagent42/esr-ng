defmodule Mix.Tasks.Ezagent.Feishu.Chat.Unbind do
  @shortdoc "Remove a Feishu chat_id ↔ session binding"
  @moduledoc """
  PR #144 SPEC v2 §5.8.

      mix ezagent.feishu.chat.unbind oc_abc123

  Drops the row from `feishu_session_bindings`. Inbound Feishu
  messages on this chat_id will subsequently be dropped (no react)
  and outbound chat sends in any session that USED to be bound to
  this chat_id will no longer mirror to Feishu.
  """
  use Mix.Task

  alias EzagentPluginFeishu.SessionBinding

  @impl Mix.Task
  def run([chat_id | _]) when is_binary(chat_id) and chat_id != "" do
    Mix.Task.run("app.start")

    case SessionBinding.unbind(chat_id) do
      :ok ->
        Mix.shell().info("✓ unbound feishu chat_id #{chat_id}")

      {:error, :not_found} ->
        Mix.raise("no binding for chat_id #{chat_id}")
    end
  end

  def run(_), do: Mix.raise("usage: mix ezagent.feishu.chat.unbind <chat_id>")
end
