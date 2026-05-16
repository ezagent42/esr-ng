defmodule Mix.Tasks.Esr.User.Create do
  @shortdoc "Create a new ESR User with password + caps"
  @moduledoc """
  Phase 4-completion Spec 05 §A.2.1 — provision a non-admin User.

  ## Usage

      mix esr.user.create user://allen \\
          --password 'temp-pw-rotate-me' \\
          --caps 'workspace.read,chat.send'

  Flags:
  - `--password <pw>` — required for login (omit only for placeholder
    rows; SessionController refuses login for password-less rows)
  - `--caps <str>` — comma-separated cap specs (see
    `Esr.Capability.Parser` for grammar). Default empty.
  - `--allow-allcaps` — required if `--caps '*'`. Prevents accidental
    admin-clones.

  ## Behavior

  1. Parses caps string via `Esr.Capability.Parser`
  2. Inserts row into `users` table (password bcrypt-hashed)
  3. If chat plugin is started and `user://` spawn fn registered,
     opportunistically spawns the User Kind live (Spec 05 Q-MU-3 default)
  4. Prints confirmation + resolved cap shapes

  ## Examples

      # Read-only operator
      mix esr.user.create user://qa --password X --caps 'workspace.read,chat.send'

      # Make a second admin (require explicit allow flag)
      mix esr.user.create user://allen2 --password X --caps '*' --allow-allcaps
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {:ok, _} = Application.ensure_all_started(:esr_core)
    {:ok, _} = Application.ensure_all_started(:esr_plugin_chat)

    {opts, positional, _} =
      OptionParser.parse(args,
        strict: [
          password: :string,
          caps: :string,
          allow_allcaps: :boolean
        ],
        aliases: []
      )

    case positional do
      [user_uri_str] when is_binary(user_uri_str) ->
        do_create(user_uri_str, opts)

      _ ->
        Mix.raise("""
        usage: mix esr.user.create <user_uri> [--password X] [--caps 'kind.behavior,...'] [--allow-allcaps]

        Example:
          mix esr.user.create user://allen --password 'pw' --caps 'workspace.read,chat.send'
        """)
    end
  end

  defp do_create(user_uri_str, opts) do
    password = Keyword.get(opts, :password)
    caps_str = Keyword.get(opts, :caps, "")
    allow_allcaps = Keyword.get(opts, :allow_allcaps, false)

    with {:ok, user_uri} <- parse_uri(user_uri_str),
         :ok <- check_allcaps_flag(caps_str, allow_allcaps),
         {:ok, caps} <- Esr.Capability.Parser.parse(caps_str, Esr.Entity.User.admin_uri()),
         {:ok, decoded} <- Esr.Users.create(user_uri, password, caps) do
      Mix.shell().info("✓ created #{user_uri_str}")
      Mix.shell().info("  caps: #{length(caps)}")
      Mix.shell().info("  password: #{if password, do: "set", else: "NOT SET (use mix esr.user.set_password)"}")
      _ = maybe_spawn_user_kind(user_uri, caps)
      Mix.shell().info("  uri: #{URI.to_string(decoded.uri)}")
    else
      {:error, reason} -> Mix.raise("create failed: #{inspect(reason)}")
    end
  end

  defp parse_uri(s) when is_binary(s) do
    case URI.new(s) do
      {:ok, %URI{scheme: "user"} = u} -> {:ok, u}
      _ -> {:error, {:bad_uri, s, "expected user://..."}}
    end
  end

  defp check_allcaps_flag(caps_str, allow_allcaps) do
    if String.contains?(caps_str, "*") and not allow_allcaps do
      {:error, :allcaps_requires_explicit_flag}
    else
      :ok
    end
  end

  defp maybe_spawn_user_kind(uri, caps) do
    if Code.ensure_loaded?(Esr.SpawnRegistry) do
      case Esr.SpawnRegistry.spawn(uri) do
        {:ok, _pid} ->
          Mix.shell().info("  spawned live User Kind at #{URI.to_string(uri)}")
          # caps are set via initial_caps; for live spawn we'd need to
          # dispatch grant_cap on Identity (Phase 5+ — Phase 4 v1 just
          # spawns; restart will re-init with stored caps from `users`).
          :ok = maybe_log_caps_not_live(caps)
          :ok

        {:error, reason} ->
          Mix.shell().info("  live spawn skipped: #{inspect(reason)}")
          :ok
      end
    else
      :ok
    end
  end

  defp maybe_log_caps_not_live([]), do: :ok

  defp maybe_log_caps_not_live(_caps) do
    Mix.shell().info(
      "  note: caps in DB but not in live Identity slice — restart picks them up via Loader"
    )

    :ok
  end
end
