defmodule Mix.Tasks.Esr.Snapshot.Dump do
  @shortdoc "Decode + print a Kind snapshot for inspection"
  @moduledoc """
  Phase 5 PR 3:

      mix esr.snapshot.dump <uri>

  Example:

      mix esr.snapshot.dump user://admin
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {:ok, _} = Application.ensure_all_started(:esr_core)

    case args do
      [uri] when is_binary(uri) ->
        case Esr.Ecto.KindSnapshot.get(uri) do
          nil ->
            Mix.raise("no snapshot at #{uri}")

          row ->
            Mix.shell().info("URI: #{row.uri}")
            Mix.shell().info("Kind: #{row.kind_type}")
            Mix.shell().info("Version: #{row.version}")
            Mix.shell().info("Updated: #{DateTime.to_iso8601(row.updated_at)}")

            Mix.shell().info(
              "Bytes: #{if is_binary(row.state_binary), do: byte_size(row.state_binary), else: 0}"
            )

            Mix.shell().info("\n--- state ---")

            case Esr.Ecto.KindSnapshot.decode_state(row) do
              {:ok, state} ->
                Mix.shell().info(inspect(state, pretty: true, limit: :infinity, width: 80))

              {:error, reason} ->
                Mix.raise("decode error: #{inspect(reason)}")
            end
        end

      _ ->
        Mix.raise("usage: mix esr.snapshot.dump <uri>")
    end
  end
end
