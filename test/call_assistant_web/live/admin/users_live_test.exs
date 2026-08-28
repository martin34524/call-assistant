defmodule CallAssistantWeb.Admin.UsersLiveTest do
  use CallAssistantWeb.ConnCase

  import Phoenix.LiveViewTest
  import CallAssistant.AccountsFixtures

  alias CallAssistant.Accounts

  test "a member is redirected away from /admin/users", %{conn: conn} do
    conn = log_in_user(conn, member_user_fixture())
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/users")
  end

  describe "as an admin" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, admin_user_fixture())}
    end

    test "lists existing users", %{conn: conn} do
      department = department_fixture(%{name: "Finance Office"})
      member = member_user_fixture(%{department: department})

      {:ok, _view, html} = live(conn, ~p"/admin/users")

      assert html =~ member.email
      assert html =~ "Finance Office"
    end

    test "creates a member user tied to a department", %{conn: conn} do
      department = department_fixture(%{name: "Finance Office"})
      {:ok, view, _html} = live(conn, ~p"/admin/users/new")

      view
      |> form("form",
        user: %{
          email: "finance-lead@example.com",
          password: "super-secret-password",
          role: "member",
          department_id: department.id
        }
      )
      |> render_submit()

      assert_patch(view, ~p"/admin/users")

      user = Accounts.get_user_by_email("finance-lead@example.com")
      assert user.role == "member"
      assert user.department_id == department.id

      assert Accounts.get_user_by_email_and_password(
               "finance-lead@example.com",
               "super-secret-password"
             )
    end

    test "creating a member without a department fails validation", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/users/new")

      html =
        view
        |> form("form",
          user: %{email: "nodept@example.com", password: "super-secret-password", role: "member"}
        )
        |> render_submit()

      assert html =~ "can&#39;t be blank"
      refute Accounts.get_user_by_email("nodept@example.com")
    end
  end
end
