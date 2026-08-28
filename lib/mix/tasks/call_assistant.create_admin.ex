defmodule Mix.Tasks.CallAssistant.CreateAdmin do
  @moduledoc """
  Creates the first admin account. There's no public self-registration in
  this app (see the plan behind the department-scoping feature) - every
  account, including the first one, is created directly.

      mix call_assistant.create_admin EMAIL PASSWORD

  The password must be at least 12 characters (same rule as any other
  account, enforced by `CallAssistant.Accounts.User.admin_changeset/2`).
  Once logged in, use the admin's "+ New user" form at /admin to create
  further accounts - this task is only for bootstrapping the very first
  one.
  """

  @shortdoc "Creates the first admin account"

  use Mix.Task

  @impl true
  def run([email, password]) do
    Mix.Task.run("app.start")

    case CallAssistant.Accounts.create_user_by_admin(%{
           "email" => email,
           "password" => password,
           "role" => "admin"
         }) do
      {:ok, user} ->
        Mix.shell().info("Created admin #{user.email}. Log in at /users/log-in.")

      {:error, changeset} ->
        Mix.shell().error("Could not create admin:")

        for {field, {message, _opts}} <- changeset.errors do
          Mix.shell().error("  #{field}: #{message}")
        end

        exit({:shutdown, 1})
    end
  end

  def run(_args) do
    Mix.shell().error("Usage: mix call_assistant.create_admin EMAIL PASSWORD")
    exit({:shutdown, 1})
  end
end
