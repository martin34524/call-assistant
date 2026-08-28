defmodule CallAssistantWeb.Admin.DashboardLiveTest do
  use CallAssistantWeb.ConnCase

  import Phoenix.LiveViewTest
  import CallAssistant.AccountsFixtures

  test "a member is redirected away from /admin", %{conn: conn} do
    conn = log_in_user(conn, member_user_fixture())
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin")
  end

  test "logged out visitors are sent to log in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin")
  end

  describe "as an admin" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, admin_user_fixture())}
    end

    test "lists every department with its member and call counts", %{conn: conn} do
      finance = department_fixture(%{name: "Finance Office"})
      department_fixture(%{name: "Store Office"})
      member_user_fixture(%{department: finance})

      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "Finance Office"
      assert html =~ "Store Office"
    end

    test "sidebar shows no escalations badge when nothing is pending", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")
      refute has_element?(view, "a[href=\"/admin/escalations\"] span.bg-error")
    end

    test "sidebar badges the escalations tab with the pending count", %{conn: conn} do
      department = department_fixture(%{name: "Finance Office"})

      {:ok, lead} =
        CallAssistant.Leads.create_lead(department, %{
          "name" => "Ada Lovelace",
          "phone" => "+15551234567"
        })

      CallAssistant.DataCase.await_background_tasks()

      {:ok, _lead} =
        CallAssistant.Leads.update_lead(lead, %{
          status: "completed",
          escalation_status: "pending",
          escalation_reason: "Asked for admin's office.",
          suggested_follow_up_goal: "Follow up."
        })

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert view
             |> element("a[href=\"/admin/escalations\"] span.bg-error")
             |> render() =~ "1"
    end

    test "creates a department", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/departments/new")

      view
      |> form("form", department: %{name: "Support"})
      |> render_submit()

      assert_patch(view, ~p"/admin")
      assert Enum.any?(CallAssistant.Departments.list_departments(), &(&1.name == "Support"))
    end
  end
end
