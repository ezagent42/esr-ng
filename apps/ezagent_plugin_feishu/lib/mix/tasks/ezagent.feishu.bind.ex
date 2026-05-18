defmodule Mix.Tasks.Ezagent.Feishu.Bind do
  @shortdoc "Bind a Feishu open_id to a local ESR user URI"
  @moduledoc """
  Phase 6 PR 15 — admin CLI for Feishu identity bindings.

      mix ezagent.feishu.bind ou_6b11faf8e9... user://linyilun
      mix ezagent.feishu.bind ou_xxx user://linyilun --admin user://admin

  After binding, the bound user receives an `Ezagent.Capability`
  authorizing dispatch into any `feishu_chat://` Kind (text / image
  / file / future-card / etc.) — see `EzagentPluginFeishu.BindingPolicy`.

  Idempotent on the (open_id, user_uri) pair — rebinding to a
  different user replaces the prior binding silently.
  """
  use Mix.Task

  alias EzagentPluginFeishu.{BindingPolicy, UserBinding}

  @impl Mix.Task
  def run(argv) do
    {opts, positional, _} = OptionParser.parse(argv, switches: [admin: :string])

    {open_id, user_uri} =
      case positional do
        [oid, uri] -> {oid, uri}
        _ -> Mix.raise("usage: mix ezagent.feishu.bind <open_id> <user_uri> [--admin <admin_uri>]")
      end

    Mix.Task.run("app.start")

    admin_uri = opts[:admin] || "user://admin"

    case UserBinding.bind(open_id, user_uri, admin_uri) do
      {:ok, _row} ->
        Mix.shell().info("✓ bound #{open_id} → #{user_uri} (by #{admin_uri})")

        case BindingPolicy.apply(user_uri, admin_uri) do
          :ok ->
            Mix.shell().info("✓ granted feishu_chat:* cap to #{user_uri}")

          err ->
            Mix.shell().error("⚠ binding saved but cap grant failed: #{inspect(err)}")
        end

      {:error, reason} ->
        Mix.raise("bind failed: #{inspect(reason)}")
    end
  end
end
