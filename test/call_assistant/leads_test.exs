defmodule CallAssistant.LeadsTest do
  use CallAssistant.DataCase

  alias CallAssistant.Leads

  @valid_attrs %{
    "name" => "Ada Lovelace",
    "phone" => "+1 555 123 4567",
    "source" => "Website form"
  }

  describe "create_lead/1" do
    test "creates a lead with a default status of new" do
      assert {:ok, lead} = Leads.create_lead(@valid_attrs)
      assert lead.name == "Ada Lovelace"
      assert lead.status == "new"
      assert lead.goal =~ "Ada Lovelace"
      await_background_tasks()
    end

    test "requires name and phone" do
      assert {:error, changeset} = Leads.create_lead(%{"name" => "", "phone" => ""})
      assert %{name: ["can't be blank"], phone: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects an invalid phone number" do
      assert {:error, changeset} =
               Leads.create_lead(%{"name" => "Ada", "phone" => "not-a-phone!!"})

      assert %{phone: [_]} = errors_on(changeset)
    end

    test "kicks off qualification and eventually reaches a terminal status" do
      Leads.subscribe()
      assert {:ok, lead} = Leads.create_lead(@valid_attrs)

      final_status = await_terminal_status(lead.id)

      assert final_status in CallAssistant.CallE.terminal_statuses()
      await_background_tasks()
    end
  end

  describe "list_leads/0" do
    test "returns leads newest first" do
      {:ok, first} = Leads.create_lead(@valid_attrs)
      {:ok, second} = Leads.create_lead(Map.put(@valid_attrs, "name", "Grace Hopper"))

      assert [%{id: second_id}, %{id: first_id}] = Leads.list_leads()
      assert second_id == second.id
      assert first_id == first.id
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
