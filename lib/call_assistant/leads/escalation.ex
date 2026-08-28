defmodule CallAssistant.Leads.Escalation do
  @moduledoc """
  Post-call handoff: after a call *completes* (see
  `CallAssistant.Leads.Qualifier`, which is the only caller of `start/1`),
  asks `CallAssistant.Claude` whether it surfaced something that needs an
  admin's attention, and if so, either:

    * flags the lead `escalation_status: "pending"` for an admin to
      review (`CallAssistantWeb.Admin.EscalationsLive`), or
    * if the classifier judged it `auto_handleable` (confident enough in
      the transcript to draft a good follow-up without a human adding
      context) and `config :call_assistant, :auto_follow_up_enabled` is
      on (the default - a kill switch, not a prompt), places the
      follow-up call itself via the normal `CallAssistant.Leads.create_lead/2`
      path, landing in `CallAssistant.Departments.admin_department/0` and
      linked back via `follow_up_of_id`.

  Runs as a supervised, unlinked `Task`, same shape as `Qualifier` itself
  - a slow or failed classification never blocks or crashes the call
  pipeline it's watching.
  """

  require Logger

  alias CallAssistant.Claude
  alias CallAssistant.Departments
  alias CallAssistant.Leads
  alias CallAssistant.Leads.Lead

  def start(%Lead{} = lead) do
    Task.Supervisor.start_child(CallAssistant.TaskSupervisor, fn -> run(lead) end)
  end

  def run(%Lead{} = lead) do
    case Claude.client().classify_call(lead) do
      {:ok, %{needs_escalation: false}} ->
        :ok

      {:ok, %{needs_escalation: true, auto_handleable: true} = classification} ->
        if Application.get_env(:call_assistant, :auto_follow_up_enabled, true) do
          auto_handle(lead, classification)
        else
          mark_pending(lead, classification)
        end

      {:ok, %{needs_escalation: true} = classification} ->
        mark_pending(lead, classification)

      {:error, reason} ->
        Logger.warning(
          "Escalation classification skipped for lead #{lead.id}: #{inspect(reason)}"
        )

        :ok
    end
  end

  defp mark_pending(lead, classification) do
    Leads.update_lead(lead, %{
      escalation_status: "pending",
      escalation_reason: classification.reason,
      suggested_follow_up_goal: classification.suggested_goal
    })
  end

  defp auto_handle(lead, classification) do
    {:ok, _lead} =
      Leads.update_lead(lead, %{
        escalation_status: "auto_handled",
        escalation_reason: classification.reason,
        suggested_follow_up_goal: classification.suggested_goal
      })

    # Reuses the exact same path a human placing a call goes through -
    # it kicks off Qualifier.start/1 itself, so the follow-up call is
    # placed immediately, not just scheduled/queued.
    Leads.create_lead(Departments.admin_department(), %{
      "name" => lead.name,
      "phone" => lead.phone,
      "goal" => classification.suggested_goal,
      "follow_up_of_id" => lead.id
    })
  end
end
