defmodule Mix.Tasks.Esr.Feishu.Unbind do
  @shortdoc "Remove a Feishu open_id binding"
  @moduledoc """
  Phase 6 PR 15.

      mix esr.feishu.unbind ou_6b11faf8e9...

  Drops the row from `feishu_user_bindings`. Does NOT revoke the cap
  the bound user received — the cap stays attached because the user
  may have other Feishu open_ids bound to them. Use
  `mix esr.user.token`-style explicit cap revocation if you want that.
  """
  use Mix.Task

  alias EsrPluginFeishu.UserBinding

  @impl Mix.Task
  def run([open_id | _]) when is_binary(open_id) and open_id != "" do
    Mix.Task.run("app.start")

    case UserBinding.unbind(open_id) do
      :ok ->
        Mix.shell().info("✓ unbound #{open_id}")

      {:error, :not_found} ->
        Mix.raise("no binding for #{open_id}")
    end
  end

  def run(_), do: Mix.raise("usage: mix esr.feishu.unbind <open_id>")
end
