defmodule CallAssistantWeb.Admin.CallsLiveTest do
  use CallAssistantWeb.ConnCase

  import Phoenix.LiveViewTest
  import CallAssistant.AccountsFixtures

  alias CallAssistant.Leads

  test "a member is redirected away from /admin/calls", %{conn: conn} do
    conn = log_in_user(conn, member_user_fixture())
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/calls")
  end

  describe "as an admin" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, admin_user_fixture())}
    end

    test "shows calls from every department", %{conn: conn} do
      finance = department_fixture(%{name: "Finance Office"})
      store = department_fixture(%{name: "Store Office"})

      {:ok, _a} =
        Leads.create_lead(finance, %{"name" => "Finance Lead", "phone" => "+15551234567"})

      {:ok, _b} = Leads.create_lead(store, %{"name" => "Store Lead", "phone" => "+15551234567"})

      {:ok, view, _html} = live(conn, ~p"/admin/calls")

      assert has_element?(view, "td", "Finance Lead")
      assert has_element?(view, "td", "Store Lead")
      CallAssistant.DataCase.await_background_tasks()
    end

    test "can place a call by picking a department directly on this page", %{conn: conn} do
      department = department_fixture(%{name: "Finance Office"})
      {:ok, view, _html} = live(conn, ~p"/admin/calls")

      view
      |> form("#new-call-form",
        lead: %{department_id: department.id, name: "Ada Lovelace", phone: "+15551234567"}
      )
      |> render_submit()

      assert has_element?(view, "td", "Ada Lovelace")
      assert [lead] = Leads.list_leads_for_department(department.id)
      assert lead.name == "Ada Lovelace"
      CallAssistant.DataCase.await_background_tasks()
    end

    test "requires a department to be picked", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/calls")

      html =
        view
        |> form("#new-call-form", lead: %{name: "Ada Lovelace", phone: "+15551234567"})
        |> render_submit()

      assert html =~ "can&#39;t be blank" or html =~ "is invalid"
    end
  end
end
