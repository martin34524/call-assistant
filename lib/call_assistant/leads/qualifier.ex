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
  alias CallAssistant.Leads.Escalation
  alias CallAssistant.Leads.Lead

  @poll_timeout_ms 5 * 60 * 1_000

  defp poll_interval_ms do
    Application.get_env(:call_assistant, :qualifier_poll_interval_ms, 1_500)
  end

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
           }) do
      handle_plan(client, lead, plan)
    else
      {:error, reason} ->
        Logger.warning("CALL-E qualification failed for lead #{lead.id}: #{inspect(reason)}")
        Leads.update_lead(lead, %{status: "failed", error: inspect(reason)})
    end
  end

  # plan_call can come back needing clarification (ambiguous goal, missing
  # details, unsupported region, ...) instead of a runnable plan - never
  # call run_call in that case, since there is no confirm_token yet.
  defp handle_plan(_client, lead, %{ready_to_run: false} = plan) do
    questions = Map.get(plan, :clarifying_questions, [])

    Leads.update_lead(lead, %{
      status: "needs_clarification",
      plan_id: plan.plan_id,
      summary: Enum.join(questions, " / ")
    })
  end

  defp handle_plan(client, lead, %{ready_to_run: true} = plan) do
    with {:ok, lead} <-
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
    cond do
      # Checked at the top of every cycle (before sleeping/polling again),
      # so a cancel takes effect within one poll interval. This can only
      # stop *us* from tracking/writing further updates - CALL-E has no
      # cancel/hangup tool, so the real call (if still live) keeps running
      # on CALL-E's side either way. See Leads.cancel/2.
      Leads.current_status(lead.id) == "cancelled" ->
        :cancelled

      System.monotonic_time(:millisecond) - started_at > @poll_timeout_ms ->
        Leads.update_lead(lead, %{status: "failed", error: "timed out waiting for call result"})

      true ->
        Process.sleep(poll_interval_ms())

        case client.get_call_run(%{call_run_id: lead.call_run_id}) do
          {:ok, %{status: status} = result} ->
            if status in CallE.terminal_statuses() do
              apply_terminal_result(lead, result)
            else
              {:ok, lead} = maybe_update_status_message(lead, Map.get(result, :message))
              poll_until_done(client, lead, started_at)
            end

          {:error, reason} ->
            Logger.warning("CALL-E polling error for lead #{lead.id}: #{inspect(reason)}")
            poll_until_done(client, lead, started_at)
        end
    end
  end

  # Only writes (and broadcasts) when the message actually changed, so a
  # call that sits at the same status for many poll cycles doesn't spam
  # the DB/PubSub with no-op updates.
  defp maybe_update_status_message(lead, message)
       when is_binary(message) and message != lead.status_message do
    Leads.update_lead(lead, %{status_message: message})
  end

  defp maybe_update_status_message(lead, _message), do: {:ok, lead}

  defp apply_terminal_result(lead, %{status: "failed"} = result) do
    Leads.update_lead(lead, %{
      status: "failed",
      status_message: Map.get(result, :message),
      transcript: Map.get(result, :transcript),
      error: Map.get(result, :summary) || "call failed"
    })
  end

  # "completed" is the only terminal status with a transcript/summary
  # worth handing to Escalation - no_answer/declined/failed never have
  # enough content for the classifier to say anything meaningful.
  defp apply_terminal_result(lead, %{status: "completed"} = result) do
    with {:ok, lead} <-
           Leads.update_lead(lead, %{
             status: "completed",
             status_message: Map.get(result, :message),
             transcript: Map.get(result, :transcript),
             summary: Map.get(result, :summary),
             task_completed: Map.get(result, :task_completed)
           }) do
      Escalation.start(lead)
      {:ok, lead}
    end
  end

  defp apply_terminal_result(lead, result) do
    Leads.update_lead(lead, %{
      status: result.status,
      status_message: Map.get(result, :message),
      transcript: Map.get(result, :transcript),
      summary: Map.get(result, :summary),
      task_completed: Map.get(result, :task_completed)
    })
  end

  defp set_status(lead, status), do: Leads.update_lead(lead, %{status: status})
end
