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
