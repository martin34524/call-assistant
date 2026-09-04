defmodule CallAssistant.Leads.Escalation do
  @moduledoc """
  Post-call handoff: after a call *completes* (see
  `CallAssistant.Leads.Qualifier`, which is the only caller of `start/1`),
  asks `CallAssistant.Claude` whether it surfaced something that needs
  attention, and - crucially - *which* department the follow-up actually
  belongs to (not always Admin: an Admin-line call can turn out to be a
  Finance request, a Finance call can turn out to need a genuine admin
  decision, etc. - see `CallAssistant.Claude.Prompt`). Either way:

    * flags the lead `escalation_status: "pending"` for an admin to
      review (`CallAssistantWeb.Admin.EscalationsLive`), with the
      classifier's suggested department pre-filled on the review form
      (an admin can still change it before placing the call), or
    * if the classifier judged it `auto_handleable` (confident enough in
      the transcript to draft a good follow-up without a human adding
      context) and `config :call_assistant, :auto_follow_up_enabled` is
      on (the default - a kill switch, not a prompt), schedules the
      follow-up call itself via the normal `CallAssistant.Leads.create_lead/2`
      path, in the resolved department, linked back via `follow_up_of_id` -
      a few minutes out (`config :call_assistant, :auto_follow_up_delay_minutes`,
      default 5), not instantly, so it's visible and cancellable before it
      actually happens rather than a silent fait accompli.

  The classifier only ever names a department by string - `resolve_department/1`
  is what turns that into a real `%Department{}` (falling back to
  `CallAssistant.Departments.admin_department/0` for `nil` or an unknown
  name), the same "never trust an id/name from outside as-is" rule the
  rest of this app follows for department scoping.

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
    department = resolve_department(classification[:suggested_department])

    Leads.update_lead(lead, %{
      escalation_status: "pending",
      escalation_reason: classification.reason,
      suggested_follow_up_goal: classification.suggested_goal,
      suggested_department_id: department.id
    })
  end

  defp auto_handle(lead, classification) do
    department = resolve_department(classification[:suggested_department])

    {:ok, _lead} =
      Leads.update_lead(lead, %{
        escalation_status: "auto_handled",
        escalation_reason: classification.reason,
        suggested_follow_up_goal: classification.suggested_goal,
        suggested_department_id: department.id
      })

    # Reuses the exact same path a human placing a call goes through -
    # create_lead/2 itself decides whether to kick off Qualifier.start/1
    # immediately or leave it for CallAssistant.Leads.Scheduler, purely
    # based on whether scheduled_at is set below.
    Leads.create_lead(department, %{
      "name" => lead.name,
      "phone" => lead.phone,
      "goal" => classification.suggested_goal,
      "follow_up_of_id" => lead.id,
      "scheduled_at" => auto_follow_up_scheduled_at()
    })
  end

  defp auto_follow_up_scheduled_at do
    delay_minutes = Application.get_env(:call_assistant, :auto_follow_up_delay_minutes, 5)
    DateTime.utc_now() |> DateTime.add(delay_minutes, :minute)
  end

  defp resolve_department(nil), do: Departments.admin_department()

  defp resolve_department(name) do
    Departments.get_department_by_name(name) || Departments.admin_department()
  end
end
