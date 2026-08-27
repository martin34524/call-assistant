defmodule CallAssistant.Leads.Qualifier do
  @moduledoc """
  Orchestrates a single lead through CALL-E's plan_call -> run_call ->
  get_call_run flow and updates the lead record as it progresses, so the
  LiveView dashboard reflects call status in real time.

  Runs as a supervised, unlinked Task per lead so multiple leads can be
  called concurrently and one failure can't take down the app.
  """

  require Logger

  alias CallAssistant.CallE
  alias CallAssistant.Leads
  alias CallAssistant.Leads.Lead

  @poll_interval_ms 1_500
  @poll_timeout_ms 5 * 60 * 1_000

  def start(%Lead{} = lead) do
    Task.Supervisor.start_child(CallAssistant.TaskSupervisor, fn -> run(lead) end)
  end

  def run(%Lead{} = lead) do
    client = CallE.client()

    with {:ok, lead} <- set_status(lead, "planning"),
         {:ok, plan} <-
           client.plan_call(%{
             to_phone: lead.phone,
             language: "en",
             goal: lead.goal
           }),
         {:ok, lead} <-
           Leads.update_lead(lead, %{
             status: "ready_to_run",
             plan_id: plan.plan_id,
             confirm_token: plan.confirm_token
           }),
         {:ok, run_info} <-
           client.run_call(%{plan_id: plan.plan_id, confirm_token: plan.confirm_token}),
         {:ok, lead} <-
           Leads.update_lead(lead, %{status: "in_progress", call_run_id: run_info.call_run_id}) do
      poll_until_done(client, lead, System.monotonic_time(:millisecond))
    else
      {:error, reason} ->
        Logger.warning("CALL-E qualification failed for lead #{lead.id}: #{inspect(reason)}")
        Leads.update_lead(lead, %{status: "failed", error: inspect(reason)})
    end
  end

  defp poll_until_done(client, lead, started_at) do
    if System.monotonic_time(:millisecond) - started_at > @poll_timeout_ms do
      Leads.update_lead(lead, %{status: "failed", error: "timed out waiting for call result"})
    else
      Process.sleep(@poll_interval_ms)

      case client.get_call_run(%{call_run_id: lead.call_run_id}) do
        {:ok, %{status: status} = result} when status in ["completed", "failed", "no_answer"] ->
          apply_terminal_result(lead, result)

        {:ok, %{status: _status}} ->
          poll_until_done(client, lead, started_at)

        {:error, reason} ->
          Logger.warning("CALL-E polling error for lead #{lead.id}: #{inspect(reason)}")
          poll_until_done(client, lead, started_at)
      end
    end
  end

  defp apply_terminal_result(lead, %{status: "no_answer", transcript: transcript}) do
    Leads.update_lead(lead, %{status: "no_answer", transcript: transcript})
  end

  defp apply_terminal_result(lead, %{status: "failed", structured_result: result}) do
    Leads.update_lead(lead, %{status: "failed", error: error_message(result)})
  end

  defp apply_terminal_result(lead, %{status: "completed", transcript: transcript, structured_result: result}) do
    interested = Map.get(result || %{}, "interested", false)

    Leads.update_lead(lead, %{
      status: if(interested, do: "qualified", else: "disqualified"),
      transcript: transcript,
      interested: interested,
      budget: Map.get(result || %{}, "budget"),
      timeline: Map.get(result || %{}, "timeline"),
      decision_maker: Map.get(result || %{}, "decision_maker"),
      callback_requested: Map.get(result || %{}, "callback_requested"),
      notes: Map.get(result || %{}, "notes")
    })
  end

  defp error_message(%{"error" => message}), do: message
  defp error_message(_), do: "call failed"

  defp set_status(lead, status), do: Leads.update_lead(lead, %{status: status})
end
