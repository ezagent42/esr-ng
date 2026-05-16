defmodule Mix.Tasks.Esr.Snapshot.Clear do
  @shortdoc "Delete a Kind snapshot row (next spawn → init_fresh)"
  @moduledoc """
  Phase 5 PR 3:

      mix esr.snapshot.clear <uri>

  Removes the snapshot row. The next time the Kind is spawned, it will
  init_fresh (granted caps / runtime state lost).
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {:ok, _} = Application.ensure_all_started(:esr_core)

    case args do
      [uri] when is_binary(uri) ->
        case Esr.Ecto.KindSnapshot.get(uri) do
          nil ->
            Mix.shell().info("no snapshot at #{uri} (nothing to clear)")

          _row ->
            :ok = Esr.Ecto.KindSnapshot.delete(uri)
            Mix.shell().info("✓ cleared snapshot at #{uri}")
        end

      _ ->
        Mix.raise("usage: mix esr.snapshot.clear <uri>")
    end
  end
end
