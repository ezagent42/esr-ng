defmodule EzagentCore.Repo do
  use Ecto.Repo,
    otp_app: :ezagent_core,
    adapter: Ecto.Adapters.SQLite3
end
