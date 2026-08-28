defmodule CallAssistantWeb.Admin.DepartmentLiveTest do
  use CallAssistantWeb.ConnCase

  import Phoenix.LiveViewTest
  import CallAssistant.AccountsFixtures

  alias CallAssistant.Leads

  setup %{conn: conn} do
    department = department_fixture(%{name: "Finance Office"})
    %{conn: log_in_user(conn, admin_user_fixture()), department: department}
  end

  test "a member is redirected away from an admin department page", %{department: department} do
    conn = Phoenix.ConnTest.build_conn() |> log_in_user(member_user_fixture())
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/departments/#{department.id}")
  end

  test "shows only this department's leads", %{conn: conn, department: department} do
    other_department = department_fixture(%{name: "Store Office"})

    {:ok, _other} =
      Leads.create_lead(other_department, %{"name" => "Not Here", "phone" => "+15551234567"})

    {:ok, _mine} = Leads.create_lead(department, %{"name" => "Here", "phone" => "+15551234567"})

    {:ok, view, _html} = live(conn, ~p"/admin/departments/#{department.id}")

    assert has_element?(view, "td", "Here")
    refute has_element?(view, "td", "Not Here")
    CallAssistant.DataCase.await_background_tasks()
  end

  test "can place a call on behalf of the department", %{conn: conn, department: department} do
    {:ok, view, _html} = live(conn, ~p"/admin/departments/#{department.id}")

    view
    |> form("#new-lead-form",
      lead: %{name: "Ada Lovelace", phone: "+15551234567", source: "Website form"}
    )
    |> render_submit()

    assert has_element?(view, "td", "Ada Lovelace")
    assert [lead] = Leads.list_leads_for_department(department.id)
    assert lead.department_id == department.id
    CallAssistant.DataCase.await_background_tasks()
  end

  test "shows the department's members with an add-member link", %{
    conn: conn,
    department: department
  } do
    member = member_user_fixture(%{department: department})

    {:ok, _view, html} = live(conn, ~p"/admin/departments/#{department.id}")

    assert html =~ member.email
    assert html =~ ~s(href="/admin/users/new?department_id=#{department.id}")
  end

  test "can remove a member directly from the department page", %{
    conn: conn,
    department: department
  } do
    member = member_user_fixture(%{department: department})
    {:ok, view, _html} = live(conn, ~p"/admin/departments/#{department.id}")

    view |> element("button", "Remove") |> render_click()

    refute CallAssistant.Accounts.get_user_by_email(member.email)
    refute has_element?(view, "li", member.email)
  end
end
