defmodule Mix.Tasks.Esr.Workspace.Create do
  @shortdoc "Spawn a Workspace Kind at workspace://<name>"
  @moduledoc """
  Phase 4b admin tool — create an in-memory Workspace.

  ## Usage

      mix esr.workspace.create <name> [members:<uri1>,<uri2>...]

  ### Examples

      # Empty workspace
      mix esr.workspace.create default

      # Workspace with declared members
      mix esr.workspace.create architect-review \\
          members:user://admin,agent://cc-architect

  Phase 4c adds persistence (workspaces table) — until then the
  Workspace lives only for the lifetime of the BEAM node.

  Phase 4c also adds `mix esr.workspace.list` / `mix esr.workspace.add_member`.
  """
  use Mix.Task

  alias Esr.Entity.Workspace, as: WK

  @impl Mix.Task
  def run(args) do
    {:ok, _} = Application.ensure_all_started(:esr_core)

    case args do
      [name | rest] when is_binary(name) and name != "" ->
        members = parse_members(rest)

        case Esr.Workspace.spawn_workspace(name, %{members: members}) do
          {:ok, pid} ->
            Mix.shell().info(
              "spawned #{URI.to_string(WK.uri_for(name))} pid=#{inspect(pid)} " <>
                "members=#{length(members)}"
            )

          {:error, {:already_started, pid}} ->
            Mix.raise(
              "workspace://#{name} already alive at #{inspect(pid)} — use a different name"
            )

          {:error, reason} ->
            Mix.raise("spawn failed: #{inspect(reason)}")
        end

      _ ->
        Mix.raise("""
        usage: mix esr.workspace.create <name> [members:<uri1>,<uri2>...]

        Examples:
            mix esr.workspace.create default
            mix esr.workspace.create architect members:user://admin,agent://cc-architect
        """)
    end
  end

  defp parse_members([]), do: []

  defp parse_members(["members:" <> csv | _rest]) do
    csv
    |> String.split(",", trim: true)
    |> Enum.map(&URI.parse/1)
  end

  defp parse_members([other | _]),
    do: Mix.raise("unrecognized arg: #{inspect(other)} (expected members:<csv>)")
end
