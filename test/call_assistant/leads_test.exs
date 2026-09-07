defmodule CallAssistant.LeadsTest do
  use CallAssistant.DataCase

  import CallAssistant.AccountsFixtures

  alias CallAssistant.Leads

  @valid_attrs %{
    "name" => "Ada Lovelace",
    "phone" => "+1 555 123 4567",
    "source" => "Website form"
  }

  setup do
    department = department_fixture(%{name: "Finance Office"})
    %{department: department, scope: member_scope_fixture(%{department: department})}
  end

  describe "create_lead/2" do
    test "creates a lead in the given department with a default status of new", %{
      department: department
    } do
      assert {:ok, lead} = Leads.create_lead(department, @valid_attrs)
      assert lead.name == "Ada Lovelace"
      assert lead.status == "new"
      assert lead.department_id == department.id
      assert lead.goal =~ "Ada Lovelace"
      assert lead.goal =~ "Hi, this is MacDevs Finance Office calling."
      await_background_tasks()
    end

    test "weaves the caller-supplied context into the goal", %{department: department} do
      attrs = Map.put(@valid_attrs, "context", "Let them know invoice #4521 is overdue.")
      assert {:ok, lead} = Leads.create_lead(department, attrs)
      assert lead.goal =~ "Let them know invoice #4521 is overdue."
      refute lead.goal =~ "budget"
      await_background_tasks()
    end

    test "does not overwrite an explicitly provided goal", %{department: department} do
      attrs = Map.put(@valid_attrs, "goal", "Custom goal text")
      assert {:ok, lead} = Leads.create_lead(department, attrs)
      assert lead.goal == "Custom goal text"
      await_background_tasks()
    end

    test "defaults language to English when unspecified", %{department: department} do
      assert {:ok, lead} = Leads.create_lead(department, @valid_attrs)
      assert lead.language == "English"
      await_background_tasks()
    end

    test "stores an explicitly chosen language", %{department: department} do
      attrs = Map.put(@valid_attrs, "language", "French")
      assert {:ok, lead} = Leads.create_lead(department, attrs)
      assert lead.language == "French"
      await_background_tasks()
    end

    test "rejects a language outside the known list", %{department: department} do
      attrs = Map.put(@valid_attrs, "language", "Klingon")
      assert {:error, changeset} = Leads.create_lead(department, attrs)
      assert %{language: ["is invalid"]} = errors_on(changeset)
    end

    test "requires name and phone", %{department: department} do
      assert {:error, changeset} = Leads.create_lead(department, %{"name" => "", "phone" => ""})
      assert %{name: ["can't be blank"], phone: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects an invalid phone number", %{department: department} do
      assert {:error, changeset} =
               Leads.create_lead(department, %{"name" => "Ada", "phone" => "not-a-phone!!"})

      assert %{phone: [_]} = errors_on(changeset)
    end

    test "kicks off qualification and eventually reaches a terminal status", %{
      department: department,
      scope: scope
    } do
      Leads.subscribe(scope)
      assert {:ok, lead} = Leads.create_lead(department, @valid_attrs)

      final_status = await_terminal_status(lead.id)

      assert final_status in CallAssistant.CallE.terminal_statuses()
      await_background_tasks()
    end
  end

  describe "list_leads/1" do
    test "returns a member's own department's leads, newest first", %{
      department: department,
      scope: scope
    } do
      {:ok, first} = Leads.create_lead(department, @valid_attrs)
      {:ok, second} = Leads.create_lead(department, Map.put(@valid_attrs, "name", "Grace Hopper"))

      assert [%{id: second_id}, %{id: first_id}] = Leads.list_leads(scope)
      assert second_id == second.id
      assert first_id == first.id
      await_background_tasks()
    end

    test "never returns another department's leads to a member scope", %{
      department: department,
      scope: scope
    } do
      other_department = department_fixture(%{name: "Store Office"})
      {:ok, _other_lead} = Leads.create_lead(other_department, @valid_attrs)
      {:ok, own_lead} = Leads.create_lead(department, @valid_attrs)

      assert [%{id: id}] = Leads.list_leads(scope)
      assert id == own_lead.id
      await_background_tasks()
    end

    test "returns every department's leads to an admin scope", %{department: department} do
      other_department = department_fixture(%{name: "Store Office"})
      {:ok, lead_a} = Leads.create_lead(department, @valid_attrs)
      {:ok, lead_b} = Leads.create_lead(other_department, @valid_attrs)

      admin_scope = admin_scope_fixture()
      ids = admin_scope |> Leads.list_leads() |> Enum.map(& &1.id)

      assert lead_a.id in ids
      assert lead_b.id in ids
      await_background_tasks()
    end
  end

  describe "get_lead!/2" do
    test "raises Ecto.NoResultsError for a lead outside the scope's department", %{
      department: department,
      scope: scope
    } do
      other_department = department_fixture(%{name: "Store Office"})
      {:ok, other_lead} = Leads.create_lead(other_department, @valid_attrs)
      {:ok, _own_lead} = Leads.create_lead(department, @valid_attrs)

      assert_raise Ecto.NoResultsError, fn -> Leads.get_lead!(scope, other_lead.id) end
      await_background_tasks()
    end

    test "an admin scope can fetch any department's lead", %{department: department} do
      {:ok, lead} = Leads.create_lead(department, @valid_attrs)

      assert %{id: id} = Leads.get_lead!(admin_scope_fixture(), lead.id)
      assert id == lead.id
      await_background_tasks()
    end
  end

  describe "cancel/2" do
    test "marks the lead cancelled and the qualifier stops overwriting it", %{
      department: department,
      scope: scope
    } do
      Leads.subscribe(scope)
      {:ok, lead} = Leads.create_lead(department, @valid_attrs)

      # Catch it right as it enters in_progress (before the mock's own
      # 2-4 poll cycles can complete it), then confirm the background
      # task really stops - not just that we wrote "cancelled" once - by
      # giving it several more poll cycles (test poll interval is 20ms)
      # and checking it's still cancelled, not flipped to whatever the
      # mock would have finished as.
      await_status(lead.id, "in_progress")
      assert {:ok, cancelled} = Leads.cancel(scope, lead.id)
      assert cancelled.status == "cancelled"
      assert cancelled.status_message =~ "may still complete this call on its own"

      Process.sleep(200)
      assert Leads.get_lead!(scope, lead.id).status == "cancelled"

      await_background_tasks()
    end

    test "raises for a lead outside the scope's department", %{department: department} do
      other_department = department_fixture(%{name: "Store Office"})
      {:ok, lead} = Leads.create_lead(other_department, @valid_attrs)

      assert_raise Ecto.NoResultsError, fn ->
        Leads.cancel(member_scope_fixture(%{department: department}), lead.id)
      end

      await_background_tasks()
    end

    test "gives an honest message for a call that was never placed (scheduled, cancelled before it fired)",
         %{department: department, scope: scope} do
      attrs = Map.put(@valid_attrs, "scheduled_at", future_time())
      {:ok, lead} = Leads.create_lead(department, attrs)

      assert {:ok, cancelled} = Leads.cancel(scope, lead.id)
      assert cancelled.status == "cancelled"
      assert cancelled.status_message == "Cancelled before the call was placed."
    end
  end

  describe "redial/3" do
    test "given the same context as before, places a new linked call with the same goal", %{
      department: department,
      scope: scope
    } do
      Leads.subscribe(scope)

      attrs =
        @valid_attrs
        |> Map.put("context", "Let them know invoice #4521 is overdue.")
        |> Map.put("language", "Spanish")

      {:ok, original} = Leads.create_lead(department, attrs)
      await_terminal_status(original.id)

      assert {:ok, redialed} = Leads.redial(scope, original.id, original.context)

      assert redialed.id != original.id
      assert redialed.follow_up_of_id == original.id
      assert redialed.name == original.name
      assert redialed.phone == original.phone
      assert redialed.source == original.source
      assert redialed.context == original.context
      assert redialed.goal == original.goal
      assert redialed.language == "Spanish"
      assert redialed.department_id == original.department_id
      assert redialed.status in ["new" | CallAssistant.CallE.terminal_statuses()]

      await_terminal_status(redialed.id)
      await_background_tasks()
    end

    test "given an edited context, places a new linked call with an updated goal", %{
      department: department,
      scope: scope
    } do
      Leads.subscribe(scope)
      attrs = Map.put(@valid_attrs, "context", "Let them know invoice #4521 is overdue.")
      {:ok, original} = Leads.create_lead(department, attrs)
      await_terminal_status(original.id)

      assert {:ok, redialed} =
               Leads.redial(scope, original.id, "Ask if they received the replacement part.")

      assert redialed.context == "Ask if they received the replacement part."
      assert redialed.goal =~ "Ask if they received the replacement part."
      refute redialed.goal == original.goal

      await_terminal_status(redialed.id)
      await_background_tasks()
    end

    test "never mutates the original lead's own history", %{
      department: department,
      scope: scope
    } do
      Leads.subscribe(scope)
      {:ok, original} = Leads.create_lead(department, @valid_attrs)
      await_terminal_status(original.id)
      # Lets a "completed" lead's own Escalation task (spawned from inside
      # the Qualifier task we just awaited) settle too, so it can't race
      # with the read below and flip escalation_status out from under us.
      await_background_tasks()
      before_redial = Leads.get_lead!(scope, original.id)

      {:ok, redialed} = Leads.redial(scope, original.id, original.context)
      await_terminal_status(redialed.id)
      await_background_tasks()

      after_redial = Leads.get_lead!(scope, original.id)
      assert after_redial.status == before_redial.status
      assert after_redial.transcript == before_redial.transcript
      assert after_redial.summary == before_redial.summary
      assert after_redial.error == before_redial.error
      assert after_redial.task_completed == before_redial.task_completed
    end

    test "raises for a lead outside the scope's department", %{department: department} do
      other_department = department_fixture(%{name: "Store Office"})
      {:ok, lead} = Leads.create_lead(other_department, @valid_attrs)

      assert_raise Ecto.NoResultsError, fn ->
        Leads.redial(member_scope_fixture(%{department: department}), lead.id, lead.context)
      end

      await_background_tasks()
    end
  end

  describe "scheduling a call" do
    test "a future scheduled_at leaves the call scheduled instead of placing it", %{
      department: department
    } do
      attrs = Map.put(@valid_attrs, "scheduled_at", future_time())

      assert {:ok, lead} = Leads.create_lead(department, attrs)
      assert lead.status == "scheduled"
      assert lead.scheduled_at
      assert lead.call_run_id == nil

      # No Qualifier task kicked off - nothing to await.
      assert Task.Supervisor.children(CallAssistant.TaskSupervisor) == []
    end

    test "a past or present scheduled_at is rejected", %{department: department} do
      attrs = Map.put(@valid_attrs, "scheduled_at", DateTime.add(DateTime.utc_now(), -1, :minute))

      assert {:error, changeset} = Leads.create_lead(department, attrs)
      assert %{scheduled_at: ["must be in the future"]} = errors_on(changeset)
    end

    test "no scheduled_at behaves exactly as before - placed immediately", %{
      department: department
    } do
      assert {:ok, lead} = Leads.create_lead(department, @valid_attrs)
      assert lead.status == "new"
      assert lead.scheduled_at == nil
      await_background_tasks()
    end
  end

  describe "place_due_scheduled_calls/0" do
    test "places a call whose scheduled time has arrived", %{department: department, scope: scope} do
      Leads.subscribe(scope)
      attrs = Map.put(@valid_attrs, "scheduled_at", DateTime.add(DateTime.utc_now(), 1, :second))
      {:ok, lead} = Leads.create_lead(department, attrs)
      assert lead.status == "scheduled"

      Process.sleep(1_100)
      Leads.place_due_scheduled_calls()

      final_status = await_terminal_status(lead.id)
      assert final_status in CallAssistant.CallE.terminal_statuses()
      await_background_tasks()
    end

    test "leaves a not-yet-due scheduled call alone", %{department: department} do
      attrs = Map.put(@valid_attrs, "scheduled_at", future_time())
      {:ok, lead} = Leads.create_lead(department, attrs)

      Leads.place_due_scheduled_calls()

      assert Leads.get_lead!(admin_scope_fixture(), lead.id).status == "scheduled"
      assert Task.Supervisor.children(CallAssistant.TaskSupervisor) == []
    end

    test "leaves a cancelled scheduled call alone even once its time has passed", %{
      department: department,
      scope: scope
    } do
      attrs = Map.put(@valid_attrs, "scheduled_at", DateTime.add(DateTime.utc_now(), 1, :second))
      {:ok, lead} = Leads.create_lead(department, attrs)
      {:ok, _cancelled} = Leads.cancel(scope, lead.id)

      Process.sleep(1_100)
      Leads.place_due_scheduled_calls()

      assert Leads.get_lead!(scope, lead.id).status == "cancelled"
      assert Task.Supervisor.children(CallAssistant.TaskSupervisor) == []
    end
  end

  defp future_time, do: DateTime.add(DateTime.utc_now(), 1, :hour)

  describe "find_matching_contacts/2" do
    test "an exact case-insensitive name match returns that contact", %{
      department: department,
      scope: scope
    } do
      {:ok, _lead} = Leads.create_lead(department, @valid_attrs)
      await_background_tasks()

      assert [%{name: "Ada Lovelace", phone: "+1 555 123 4567"}] =
               Leads.find_matching_contacts(scope, "ada lovelace")
    end

    test "falls back to a \"contains\" match when nothing matches exactly", %{
      department: department,
      scope: scope
    } do
      {:ok, _lead} = Leads.create_lead(department, @valid_attrs)
      await_background_tasks()

      assert [%{name: "Ada Lovelace"}] = Leads.find_matching_contacts(scope, "ada")
    end

    test "returns [] when nothing matches", %{scope: scope} do
      assert [] = Leads.find_matching_contacts(scope, "Nobody Here")
    end

    test "the same name called multiple times with the same number surfaces once", %{
      department: department,
      scope: scope
    } do
      {:ok, _first} = Leads.create_lead(department, @valid_attrs)
      {:ok, _second} = Leads.create_lead(department, @valid_attrs)
      await_background_tasks()

      assert [%{name: "Ada Lovelace"}] = Leads.find_matching_contacts(scope, "Ada Lovelace")
    end

    test "the same name with genuinely different numbers surfaces both", %{
      department: department,
      scope: scope
    } do
      {:ok, _first} = Leads.create_lead(department, @valid_attrs)

      {:ok, _second} =
        Leads.create_lead(department, Map.put(@valid_attrs, "phone", "+1 555 999 0000"))

      await_background_tasks()

      contacts = Leads.find_matching_contacts(scope, "Ada Lovelace")
      assert length(contacts) == 2
    end

    test "a member never matches another department's contacts", %{
      department: department,
      scope: scope
    } do
      other_department = department_fixture(%{name: "Store Office"})
      {:ok, _lead} = Leads.create_lead(other_department, @valid_attrs)
      await_background_tasks()

      assert [] = Leads.find_matching_contacts(scope, "Ada Lovelace")
      refute department == other_department
    end

    test "an admin scope matches contacts across every department", %{department: department} do
      {:ok, _lead} = Leads.create_lead(department, @valid_attrs)
      await_background_tasks()

      assert [%{name: "Ada Lovelace"}] =
               Leads.find_matching_contacts(admin_scope_fixture(), "Ada Lovelace")
    end
  end

  defp await_status(lead_id, target, deadline \\ System.monotonic_time(:millisecond) + 5_000) do
    receive do
      {:lead_updated, %{id: ^lead_id, status: ^target}} ->
        :ok

      {:lead_updated, %{id: ^lead_id}} ->
        await_status(lead_id, target, deadline)
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        flunk("timed out waiting for lead #{lead_id} to reach status #{target}")
    end
  end

  defp await_terminal_status(lead_id, deadline \\ System.monotonic_time(:millisecond) + 5_000) do
    receive do
      {:lead_updated, %{id: ^lead_id, status: status}} ->
        if status in CallAssistant.CallE.terminal_statuses() do
          status
        else
          await_terminal_status(lead_id, deadline)
        end
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        flunk("timed out waiting for lead #{lead_id} to reach a terminal status")
    end
  end
end
