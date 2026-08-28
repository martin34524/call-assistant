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
