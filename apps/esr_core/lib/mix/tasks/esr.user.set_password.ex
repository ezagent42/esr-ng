defmodule Mix.Tasks.Esr.User.SetPassword do
  @shortdoc "Set or rotate an ESR User's password"
  @moduledoc """
  Phase 4-completion Spec 05 §A.2.5 — set admin's first password
  (migration seeds admin with empty hash; this task is the path to
  enable admin login) or rotate any user's password.

  ## Usage

      mix esr.user.set_password user://admin --password 'admin-pw'
      mix esr.user.set_password user://allen --password 'new-pw'
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {:ok, _} = Application.ensure_all_started(:esr_core)

    {opts, positional, _} =
      OptionParser.parse(args, strict: [password: :string])

    with [user_uri_str] <- positional,
         password when is_binary(password) and password != "" <-
           Keyword.get(opts, :password) do
      do_set(user_uri_str, password)
    else
      _ ->
        Mix.raise("""
        usage: mix esr.user.set_password <user_uri> --password <pw>
        """)
    end
  end

  defp do_set(user_uri_str, password) do
    case Esr.Users.set_password(user_uri_str, password) do
      {:ok, _decoded} ->
        Mix.shell().info("✓ password set for #{user_uri_str}")

      {:error, :not_found} ->
        Mix.raise("user #{user_uri_str} not found")

      {:error, reason} ->
        Mix.raise("set_password failed: #{inspect(reason)}")
    end
  end
end
