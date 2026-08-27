defmodule CallAssistant.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CallAssistantWeb.Telemetry,
      CallAssistant.Repo,
      {DNSCluster, query: Application.get_env(:call_assistant, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: CallAssistant.PubSub},
      # Start a worker by calling: CallAssistant.Worker.start_link(arg)
      # {CallAssistant.Worker, arg},
      # Start to serve requests, typically the last entry
      CallAssistantWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CallAssistant.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CallAssistantWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
