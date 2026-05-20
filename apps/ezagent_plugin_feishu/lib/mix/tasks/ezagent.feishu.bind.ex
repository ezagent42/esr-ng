defmodule Mix.Tasks.Ezagent.Feishu.Bind do
  @shortdoc "Bind a Feishu open_id to a local ESR user URI"
  @moduledoc """
  Phase 6 PR 15 — admin CLI for Feishu identity bindings.

      mix ezagent.feishu.bind ou_6b11faf8e9... entity://user/default/linyilun
      mix ezagent.feishu.bind ou_xxx entity://user/default/linyilun --admin entity://user/default/admin

  After binding, `EzagentPluginFeishu.BindingPolicy.apply/2` ensures
  the bound user has `Ezagent.Entity.User.default_caps/0` (the
  baseline `kind=:session, behavior=:any` cap). With those caps the
  user can dispatch into sessions; per-session reach is controlled
  by the chat_id ↔ session_uri binding in `feishu_session_bindings`
  (see `mix ezagent.feishu.chat.bind`).

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

    admin_uri = opts[:admin] || "entity://user/default/admin"

    case UserBinding.bind(open_id, user_uri, admin_uri) do
      {:ok, _row} ->
        Mix.shell().info("✓ bound #{open_id} → #{user_uri} (by #{admin_uri})")

        case BindingPolicy.apply(user_uri, admin_uri) do
          :ok ->
            Mix.shell().info("✓ ensured default session-participation caps for #{user_uri}")

          err ->
            Mix.shell().error("⚠ binding saved but cap grant failed: #{inspect(err)}")
        end

      {:error, reason} ->
        Mix.raise("bind failed: #{inspect(reason)}")
    end
  end
end
