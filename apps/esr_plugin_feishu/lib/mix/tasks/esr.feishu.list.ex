defmodule Mix.Tasks.Esr.Feishu.List do
  @shortdoc "List all Feishu open_id → local user bindings"
  @moduledoc """
  Phase 6 PR 15.

      mix esr.feishu.list
  """
  use Mix.Task

  alias EsrPluginFeishu.UserBinding

  @impl Mix.Task
  def run(_argv) do
    Mix.Task.run("app.start")

    case UserBinding.list_all() do
      [] ->
        Mix.shell().info("(no bindings)")

      rows ->
        Mix.shell().info("Feishu user bindings:")

        Enum.each(rows, fn r ->
          Mix.shell().info(
            "  #{r.open_id} → #{r.user_uri}   bound_by=#{r.bound_by} at=#{DateTime.to_iso8601(r.bound_at)}"
          )
        end)
    end
  end
end
