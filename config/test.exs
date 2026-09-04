import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :call_assistant, CallAssistant.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "call_assistant_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :call_assistant, CallAssistantWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "KF9fQLkEdU6g1SgfPUMHZlbdk2Nq7bldkryFtJAo6/KJt5b6mpjMRycAqPrOflQi",
  server: false

# In test we don't send emails
config :call_assistant, CallAssistant.Mailer, adapter: Swoosh.Adapters.Test

# Always use the mock CALL-E adapter in tests, regardless of the app's
# general default (config.exs) - tests must never shell out to the real
# `calle` CLI or place real phone calls.
config :call_assistant, :call_e_client, CallAssistant.CallE.Mock

# Same for the escalation classifier - tests must never call the real
# Claude API.
config :call_assistant, :claude_client, CallAssistant.Claude.Mock

# Poll the mock CALL-E adapter quickly so tests run fast.
config :call_assistant, :qualifier_poll_interval_ms, 20

# CallAssistant.Leads.Scheduler is a long-lived singleton started once at
# boot, not per-test like Qualifier's Task-based workers - it has no Ecto
# Sandbox checkout of its own. Tests call CallAssistant.Leads.place_due_scheduled_calls/0
# directly instead of waiting on this timer, so keep it long enough that it
# never actually ticks (and hits the DB with no sandbox connection) during
# a test run, rather than disabling the process entirely.
config :call_assistant, :scheduler_poll_interval_ms, :timer.hours(1)

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
