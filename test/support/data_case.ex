defmodule CallAssistant.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use CallAssistant.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias CallAssistant.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import CallAssistant.DataCase
    end
  end

  setup tags do
    CallAssistant.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(CallAssistant.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  @doc """
  Waits for every child of `CallAssistant.TaskSupervisor` to finish.

  Tests that trigger `CallAssistant.Leads.Qualifier` (directly, or via
  `Leads.create_lead/1`) spawn a background task that keeps using the
  sandboxed DB connection after a test's assertions are satisfied. The
  sandbox connection is tied to the test process itself, so it's
  invalidated the moment the test process exits - `on_exit` callbacks run
  too late to help, since ExUnit runs them in a separate process only
  after the test process has already finished. Call this explicitly at
  the end of any test body that spawns a qualification task (directly or
  via `Leads.create_lead/1`), before the test returns.
  """
  def await_background_tasks(supervisor \\ CallAssistant.TaskSupervisor) do
    case Task.Supervisor.children(supervisor) do
      [] ->
        :ok

      pids ->
        Enum.each(pids, fn pid ->
          ref = Process.monitor(pid)

          receive do
            {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
          after
            2_000 -> Process.demonitor(ref, [:flush])
          end
        end)

        await_background_tasks(supervisor)
    end
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
