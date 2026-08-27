defmodule CallAssistant.Repo do
  use Ecto.Repo,
    otp_app: :call_assistant,
    adapter: Ecto.Adapters.Postgres
end
