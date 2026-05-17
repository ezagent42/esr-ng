defmodule Mix.Tasks.Esr.Home.ImportFromEsrdDev do
  @shortdoc "Migrate old ~/.esrd-dev/<profile> credentials/bindings into ESR_HOME"
  @moduledoc """
  Phase 5 PR 1 helper for operators with an existing `~/.esrd-dev` setup.

  Reads:
  - `~/.esrd-dev/<profile>/adapters/esr_helper_dev/config.yaml` → Feishu credentials
  - `~/.esrd-dev/<profile>/chat_attached.yaml` → initial session ↔ chat bindings
    (parked at `$ESR_HOME/<profile>/plugins/feishu/initial_bindings.yaml`
    for Phase 5 PR 6 to seed when feishu plugin starts)

  Writes:
  - `$ESR_HOME/<profile>/credentials/feishu.yaml`
  - `$ESR_HOME/<profile>/plugins/feishu/initial_bindings.yaml`

  Does NOT delete the old `~/.esrd-dev` directory — operator decides
  when to clean up after Phase 5 has been validated end-to-end.

      mix esr.home.import_from_esrd_dev
      mix esr.home.import_from_esrd_dev --src ~/.esrd-dev/default --profile staging
  """
  use Mix.Task

  alias Esr.Home

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: [src: :string, profile: :string])
    src = opts[:src] || Path.expand("~/.esrd-dev/default")
    unless File.dir?(src), do: Mix.raise("source directory not found: #{src}")

    # Ensure target home initialized.
    unless Home.initialized?() do
      Mix.shell().info("ESR_HOME not initialized — running mix esr.home.init first")
      Mix.Task.run("esr.home.init")
    end

    import_feishu_credentials(src)
    import_chat_attached(src)

    Mix.shell().info("")
    Mix.shell().info("Imported from: #{src}")
    Mix.shell().info("Old esrd-dev directory left intact for verification.")
  end

  defp import_feishu_credentials(src) do
    config_file = Path.join(src, "adapters/esr_helper_dev/config.yaml")

    case YamlElixir.read_from_file(config_file) do
      {:ok, %{"config" => %{"app_id" => app_id, "app_secret" => app_secret} = cfg}} ->
        body = """
        # Imported from #{config_file} at #{DateTime.utc_now() |> DateTime.to_iso8601()}
        app_id: #{app_id}
        app_secret: #{app_secret}
        encrypt_key: #{Map.get(cfg, "encrypt_key", "")}
        verification_token: #{Map.get(cfg, "verification_token", "")}
        """

        target = Path.join(Home.path(:credentials), "feishu.yaml")
        File.write!(target, body)
        File.chmod!(target, 0o600)
        Mix.shell().info("  ✓ feishu.yaml ← #{config_file}")

      {:ok, _} ->
        Mix.shell().info("  ✗ #{config_file} present but missing app_id/app_secret — skipped")

      {:error, :enoent} ->
        Mix.shell().info("  • no Feishu config at #{config_file} — skipped")

      {:error, reason} ->
        Mix.shell().info("  ✗ failed to read #{config_file}: #{inspect(reason)}")
    end
  end

  defp import_chat_attached(src) do
    chat_file = Path.join(src, "chat_attached.yaml")

    case YamlElixir.read_from_file(chat_file) do
      {:ok, %{"chat_attached" => entries}} when is_list(entries) ->
        plugins_dir = Path.join([Home.path(:plugins), "feishu"])
        File.mkdir_p!(plugins_dir)
        target = Path.join(plugins_dir, "initial_bindings.yaml")

        body =
          """
          # Imported from #{chat_file} at #{DateTime.utc_now() |> DateTime.to_iso8601()}
          # Phase 5 PR 6 (esr_plugin_feishu) will seed these into RoutingRegistry
          # via feishu.chat_binding Template Class on first start.
          bindings:
          """ <>
            Enum.map_join(entries, "", fn entry ->
              app = Map.get(entry, "app_id", "")
              chat = Map.get(entry, "chat_id", "")
              current = Map.get(entry, "current", "")

              "  - app_id: #{app}\n    chat_id: #{chat}\n    old_session_id: #{current}\n"
            end)

        File.write!(target, body)
        Mix.shell().info("  ✓ plugins/feishu/initial_bindings.yaml ← #{chat_file} (#{length(entries)} entries)")

      {:error, :enoent} ->
        Mix.shell().info("  • no chat_attached.yaml at #{chat_file} — skipped")

      other ->
        Mix.shell().info("  ✗ unexpected shape in #{chat_file}: #{inspect(other)}")
    end
  end
end
