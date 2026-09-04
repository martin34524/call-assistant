defmodule CallAssistant.Leads.Scheduler do
  @moduledoc """
  Polls for scheduled calls that have come due and places them. Deliberately
  thin - all the real logic lives in `CallAssistant.Leads.place_due_scheduled_calls/0`,
  so it's testable with no GenServer timing involved; this module is just
  the timer that calls it.
  """

  use GenServer

  alias CallAssistant.Leads

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_check()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check, state) do
    Leads.place_due_scheduled_calls()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check, poll_interval_ms())
  end

  defp poll_interval_ms do
    Application.get_env(:call_assistant, :scheduler_poll_interval_ms, 30_000)
  end
end
