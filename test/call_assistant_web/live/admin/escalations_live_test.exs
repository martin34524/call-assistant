defmodule CallAssistantWeb.Admin.EscalationsLiveTest do
  use CallAssistantWeb.ConnCase

  import Phoenix.LiveViewTest
  import CallAssistant.AccountsFixtures

  alias CallAssistant.Leads

  test "a member is redirected away from /admin/escalations", %{conn: conn} do
    conn = log_in_user(conn, member_user_fixture())
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/escalations")
  end

  describe "as an admin" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, admin_user_fixture())}
    end

    defp pending_lead_fixture(department) do
      {:ok, lead} =
        Leads.create_lead(department, %{"name" => "Ada Lovelace", "phone" => "+15551234567"})

      CallAssistant.DataCase.await_background_tasks()

      {:ok, lead} =
        Leads.update_lead(lead, %{
          status: "completed",
          escalation_status: "pending",
          escalation_reason: "Asked for admin's office.",
          suggested_follow_up_goal: "Follow up with Ada Lovelace about their request."
        })

      lead
    end

    test "lists leads awaiting review with the classifier's suggested reason", %{conn: conn} do
      department = department_fixture(%{name: "Finance Office"})
      lead = pending_lead_fixture(department)

      {:ok, view, html} = live(conn, ~p"/admin/escalations")

      assert html =~ "Needs your review"
      assert has_element?(view, "*", lead.name)
      assert has_element?(view, "*", lead.escalation_reason)
    end

    test "shows nothing pending when there is nothing to review", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/escalations")
      assert html =~ "Nothing waiting on you right now."
    end

    test "submitting the review form places a linked follow-up call and clears the item", %{
      conn: conn
    } do
      department = department_fixture(%{name: "Finance Office"})
      lead = pending_lead_fixture(department)

      {:ok, view, _html} = live(conn, ~p"/admin/escalations")

      view
      |> form("#follow-up-form-#{lead.id}", %{
        "lead_#{lead.id}" => %{"goal" => "Call Ada back about scheduling."}
      })
      |> render_submit()

      assert render(view) =~ "Nothing waiting on you right now."

      resolved = Leads.get_lead!(admin_scope_fixture(), lead.id)
      assert resolved.escalation_status == "resolved"

      admin_department = CallAssistant.Departments.admin_department()
      assert [follow_up] = Leads.list_leads_for_department(admin_department.id)
      assert follow_up.follow_up_of_id == lead.id
      assert follow_up.goal == "Call Ada back about scheduling."

      CallAssistant.DataCase.await_background_tasks()
    end

    test "dismissing a pending item resolves it without placing a call", %{conn: conn} do
      department = department_fixture(%{name: "Finance Office"})
      lead = pending_lead_fixture(department)

      {:ok, view, _html} = live(conn, ~p"/admin/escalations")

      view
      |> element("button[phx-value-id=\"#{lead.id}\"]")
      |> render_click()

      assert render(view) =~ "Nothing waiting on you right now."

      resolved = Leads.get_lead!(admin_scope_fixture(), lead.id)
      assert resolved.escalation_status == "resolved"

      admin_department = CallAssistant.Departments.admin_department()
      assert Leads.list_leads_for_department(admin_department.id) == []
    end

    test "shows auto-handled leads with a link to the follow-up call they spawned", %{conn: conn} do
      department = department_fixture(%{name: "Finance Office"})

      {:ok, lead} =
        Leads.create_lead(department, %{"name" => "Grace Hopper", "phone" => "+15551234567"})

      CallAssistant.DataCase.await_background_tasks()

      {:ok, lead} =
        Leads.update_lead(lead, %{
          status: "completed",
          transcript: "USER: just handle it, ESCALATE_AUTO",
          summary: "Wants a meeting scheduled."
        })

      assert {:ok, follow_up} = CallAssistant.Leads.Escalation.run(lead)
      CallAssistant.DataCase.await_background_tasks()

      {:ok, view, html} = live(conn, ~p"/admin/escalations")

      assert html =~ "Auto-handled"
      assert has_element?(view, "*", lead.name)
      assert has_element?(view, "a[href=\"/leads/#{follow_up.id}\"]")
    end
  end
end
