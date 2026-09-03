defmodule CallAssistantWeb.Admin.ReportsLiveTest do
  use CallAssistantWeb.ConnCase

  import Phoenix.LiveViewTest
  import CallAssistant.AccountsFixtures

  alias CallAssistant.Leads

  test "a member is redirected away from /admin/reports", %{conn: conn} do
    conn = log_in_user(conn, member_user_fixture())
    assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, ~p"/admin/reports")
  end

  test "breaks down outcomes per department", %{conn: conn} do
    finance = department_fixture(%{name: "Finance Office"})
    store = department_fixture(%{name: "Store Office"})
    {:ok, _a} = Leads.create_lead(finance, %{"name" => "Finance Lead", "phone" => "+15551234567"})
    {:ok, _b} = Leads.create_lead(store, %{"name" => "Store Lead", "phone" => "+15551234567"})

    {:ok, _view, html} = live(log_in_user(conn, admin_user_fixture()), ~p"/admin/reports")

    assert html =~ "Finance Office"
    assert html =~ "Store Office"
    assert html =~ "Total leads"
    CallAssistant.DataCase.await_background_tasks()
  end
end
