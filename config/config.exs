# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :call_assistant,
  ecto_repos: [CallAssistant.Repo],
  generators: [timestamp_type: :utc_datetime]

# The verified, working CALL-E integration: shells out to the `calle` CLI
# (requires `calle auth login` to have been run once on this machine -
# see `calle auth status`). Every lead submitted through the dashboard
# places a REAL phone call. Pinned back to the Mock adapter for the test
# env below, and overridden at runtime (see config/runtime.exs) if
# CALLE_API_BASE_URL and CALLE_API_KEY are both set (speculative REST
# adapter, see lib/call_assistant/call_e/live.ex).
config :call_assistant, :call_e_client, CallAssistant.CallE.Cli

# Configure the endpoint
config :call_assistant, CallAssistantWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: CallAssistantWeb.ErrorHTML, json: CallAssistantWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: CallAssistant.PubSub,
  live_view: [signing_salt: "rZotZnyq"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :call_assistant, CallAssistant.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  call_assistant: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  call_assistant: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
