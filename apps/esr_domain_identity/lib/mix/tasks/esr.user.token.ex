defmodule Mix.Tasks.Esr.User.Token do
  @shortdoc "Rotate or revoke a user's CLI bearer token"
  @moduledoc """
  Phase 6 PR 7 — manage per-user CLI bearer tokens for `mix esr`.

  ## Usage

      mix esr.user.token <user_uri> --rotate
      mix esr.user.token <user_uri> --revoke

  ## Examples

      mix esr.user.token user://admin --rotate
      mix esr.user.token user://alice --revoke

  ## After rotating

  Pass the token to CLI calls:

      ESR_USER_TOKEN=esr_pat_xxx mix esr session create test
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
        _ -> Mix.raise("usage: mix esr.user.token <user_uri> --rotate|--revoke")
      end

    # Boot the app so Repo is up
    Mix.Task.run("app.start")

    cond do
      opts[:rotate] ->
        case Esr.Users.rotate_cli_token(uri) do
          {:ok, token} ->
            Mix.shell().info("Rotated CLI token for #{uri}.")
            Mix.shell().info("")
            Mix.shell().info("  #{token}")
            Mix.shell().info("")
            Mix.shell().info("Record this token now — it won't be shown again.")
            Mix.shell().info("Use via: ESR_USER_TOKEN=<token> mix esr ...")

          {:error, :not_found} ->
            Mix.raise("user not found: #{uri} (create with `mix esr.user.create` first)")
        end

      opts[:revoke] ->
        case Esr.Users.revoke_cli_token(uri) do
          :ok -> Mix.shell().info("Revoked CLI token for #{uri}.")
          {:error, :not_found} -> Mix.raise("user not found: #{uri}")
        end

      true ->
        Mix.raise("must pass --rotate or --revoke")
    end
  end
end
