ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(EsrCore.Repo, :manual)

# CLI tests exercise TreeBuilder + Dispatch which depend on plugins
# (chat, echo) having registered their Behaviors at boot. esr_cli's
# mix deps don't include those (CLI is supposed to be transport-only),
# so explicitly start them here.
for app <- [:esr_plugin_chat, :esr_plugin_echo, :esr_plugin_cc_pty, :esr_plugin_cc_channel, :esr_plugin_feishu] do
  case Application.ensure_all_started(app) do
    {:ok, _} -> :ok
    {:error, _} -> :ok
  end
end
