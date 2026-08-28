defmodule CallAssistantWeb.ReportsLiveTest do
  use CallAssistantWeb.ConnCase

  import Phoenix.LiveViewTest
  import CallAssistant.AccountsFixtures

  alias CallAssistant.Leads

  test "an admin visiting /reports is sent to /admin/reports", %{conn: conn} do
    conn = log_in_user(conn, admin_user_fixture())
    assert {:error, {:redirect, %{to: "/admin/reports"}}} = live(conn, ~p"/reports")
  end

  test "shows only the member's own department's outcome breakdown", %{conn: conn} do
    department = department_fixture(%{name: "Finance Office"})
    other = department_fixture(%{name: "Store Office"})
    user = member_user_fixture(%{department: department})

    {:ok, _a} = Leads.create_lead(department, %{"name" => "Mine", "phone" => "+15551234567"})
    {:ok, _b} = Leads.create_lead(other, %{"name" => "Not mine", "phone" => "+15551234567"})

    {:ok, _view, html} = live(log_in_user(conn, user), ~p"/reports")

    assert html =~ "Finance Office"
    assert html =~ "Total leads"
    CallAssistant.DataCase.await_background_tasks()
  end
end
