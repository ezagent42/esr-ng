defmodule EsrCore.Repo do
  use Ecto.Repo,
    otp_app: :esr_core,
    adapter: Ecto.Adapters.SQLite3
end
