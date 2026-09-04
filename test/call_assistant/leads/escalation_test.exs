defmodule CallAssistant.Leads.EscalationTest do
  use CallAssistant.DataCase

  import CallAssistant.AccountsFixtures

  alias CallAssistant.Leads
  alias CallAssistant.Leads.Escalation

  setup do
    department = department_fixture(%{name: "Finance Office"})

    {:ok, lead} =
      Leads.create_lead(department, %{"name" => "Ada Lovelace", "phone" => "+15551234567"})

    await_background_tasks()
    %{department: department, lead: lead}
  end

  defp complete(lead, transcript, summary) do
    {:ok, lead} =
      Leads.update_lead(lead, %{status: "completed", transcript: transcript, summary: summary})

    lead
  end

  test "a plain completed call is left alone", %{lead: lead} do
    lead = complete(lead, "USER: sounds good, thanks.", "Nothing unusual.")

    assert :ok = Escalation.run(lead)

    reloaded = Leads.get_lead!(admin_scope_fixture(), lead.id)
    assert reloaded.escalation_status == nil
  end

  test "an \"ESCALATE\" transcript marks the lead pending for admin review", %{lead: lead} do
    lead =
      complete(lead, "USER: I need to speak to ESCALATE please.", "Asked for admin's office.")

    assert {:ok, updated} = Escalation.run(lead)
    assert updated.escalation_status == "pending"
    assert updated.escalation_reason =~ "admin's office"
    assert updated.suggested_follow_up_goal =~ "Ada Lovelace"

    await_background_tasks()
  end

  test "an \"ESCALATE_AUTO\" transcript places a linked follow-up call automatically", %{
    lead: lead,
    department: department
  } do
    Leads.subscribe(admin_scope_fixture())
    lead = complete(lead, "USER: just handle it, ESCALATE_AUTO", "Wants a meeting scheduled.")

    assert {:ok, follow_up} = Escalation.run(lead)

    original = Leads.get_lead!(admin_scope_fixture(), lead.id)
    assert original.escalation_status == "auto_handled"
    assert original.escalation_reason =~ "approve"

    assert follow_up.follow_up_of_id == lead.id
    admin_department = CallAssistant.Departments.admin_department()
    assert follow_up.department_id == admin_department.id
    refute follow_up.department_id == department.id
    assert follow_up.goal =~ original.summary

    # Scheduled a few minutes out, not placed instantly - visible and
    # cancellable before it actually happens.
    assert follow_up.status == "scheduled"
    assert follow_up.scheduled_at
    assert DateTime.after?(follow_up.scheduled_at, DateTime.utc_now())
    assert Task.Supervisor.children(CallAssistant.TaskSupervisor) == []

    await_background_tasks()
  end

  test "\"ESCALATE_AUTO\" respects a configured auto-follow-up delay", %{lead: lead} do
    Application.put_env(:call_assistant, :auto_follow_up_delay_minutes, 30)
    on_exit(fn -> Application.delete_env(:call_assistant, :auto_follow_up_delay_minutes) end)

    lead = complete(lead, "USER: just handle it, ESCALATE_AUTO", "Wants a meeting scheduled.")
    assert {:ok, follow_up} = Escalation.run(lead)

    expected = DateTime.add(DateTime.utc_now(), 30, :minute)
    assert_in_delta DateTime.diff(follow_up.scheduled_at, expected, :second), 0, 5

    await_background_tasks()
  end

  test "auto-handleable but the kill switch is off falls back to pending", %{lead: lead} do
    Application.put_env(:call_assistant, :auto_follow_up_enabled, false)
    on_exit(fn -> Application.put_env(:call_assistant, :auto_follow_up_enabled, true) end)

    lead = complete(lead, "USER: just handle it, ESCALATE_AUTO", "Wants a meeting scheduled.")

    assert {:ok, updated} = Escalation.run(lead)
    assert updated.escalation_status == "pending"

    await_background_tasks()
  end

  test "\"ESCALATE_TO:<name>\" auto-routes the follow-up to that real department, not Admin", %{
    lead: lead
  } do
    store = department_fixture(%{name: "Store Office"})

    lead =
      complete(
        lead,
        "USER: actually I need the Store team, ESCALATE_AUTO ESCALATE_TO[Store Office]",
        "Wrong department, needs Store."
      )

    assert {:ok, follow_up} = Escalation.run(lead)

    original = Leads.get_lead!(admin_scope_fixture(), lead.id)
    assert original.suggested_department_id == store.id

    assert follow_up.department_id == store.id
    refute follow_up.department_id == CallAssistant.Departments.admin_department().id

    await_background_tasks()
  end

  test "an unknown suggested department name falls back to Admin instead of crashing", %{
    lead: lead
  } do
    lead =
      complete(
        lead,
        "USER: needs a team that doesn't exist. ESCALATE_TO[Nonexistent Team]",
        "Made-up department name from the classifier."
      )

    assert {:ok, updated} = Escalation.run(lead)
    assert updated.escalation_status == "pending"
    assert updated.suggested_department_id == CallAssistant.Departments.admin_department().id

    await_background_tasks()
  end

  test "\"ESCALATE_TO:<name>\" without _AUTO marks pending with that department pre-filled", %{
    lead: lead
  } do
    store = department_fixture(%{name: "Store Office"})

    lead =
      complete(
        lead,
        "USER: I actually need Store. ESCALATE_TO[Store Office]",
        "Wrong department, needs Store."
      )

    assert {:ok, updated} = Escalation.run(lead)
    assert updated.escalation_status == "pending"
    assert updated.suggested_department_id == store.id

    await_background_tasks()
  end
end
