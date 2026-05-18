defmodule Mix.Tasks.Ezagent.User.Token do
  @shortdoc "Rotate or revoke a user's CLI bearer token"
  @moduledoc """
  Phase 6 PR 7 — manage per-user CLI bearer tokens for `mix esr`.

  ## Usage

      mix ezagent.user.token <user_uri> --rotate
      mix ezagent.user.token <user_uri> --revoke

  ## Examples

      mix ezagent.user.token user://admin --rotate
      mix ezagent.user.token user://alice --revoke

  ## After rotating

  Pass the token to CLI calls:

      EZAGENT_USER_TOKEN=esr_pat_xxx mix esr session create test
      mix esr session create test --token=esr_pat_xxx

  No token = falls back to admin caps (single-user backward-compat mode).
  """
  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    {opts, args, _} = OptionParser.parse(argv, switches: [rotate: :boolean, revoke: :boolean])

    uri =
      case args do
        [uri] -> uri
        _ -> Mix.raise("usage: mix ezagent.user.token <user_uri> --rotate|--revoke")
      end

    # Boot the app so Repo is up
    Mix.Task.run("app.start")

    cond do
      opts[:rotate] ->
        case Ezagent.Users.rotate_cli_token(uri) do
          {:ok, token} ->
            Mix.shell().info("Rotated CLI token for #{uri}.")
            Mix.shell().info("")
            Mix.shell().info("  #{token}")
            Mix.shell().info("")
            Mix.shell().info("Record this token now — it won't be shown again.")
            Mix.shell().info("Use via: EZAGENT_USER_TOKEN=<token> mix esr ...")

          {:error, :not_found} ->
            Mix.raise("user not found: #{uri} (create with `mix ezagent.user.create` first)")
        end

      opts[:revoke] ->
        case Ezagent.Users.revoke_cli_token(uri) do
          :ok -> Mix.shell().info("Revoked CLI token for #{uri}.")
          {:error, :not_found} -> Mix.raise("user not found: #{uri}")
        end

      true ->
        Mix.raise("must pass --rotate or --revoke")
    end
  end
end
