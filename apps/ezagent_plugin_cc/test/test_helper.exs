ExUnit.start()

# PR #146: enable Sandbox manual mode so tests that spawn Kinds with
# `persistence :on_terminate` (e.g. `Ezagent.Entity.Agent` in
# pty_input_dispatch_test) can check out a DB connection via
# `EzagentCore.DataCase`.
Ecto.Adapters.SQL.Sandbox.mode(EzagentCore.Repo, :manual)
