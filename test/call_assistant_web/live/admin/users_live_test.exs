defmodule CallAssistantWeb.Admin.UsersLiveTest do
  use CallAssistantWeb.ConnCase

  import Phoenix.LiveViewTest
  import CallAssistant.AccountsFixtures

  alias CallAssistant.Accounts
  alias CallAssistant.Accounts.UserToken
  alias CallAssistant.Repo

  test "a member is redirected away from /admin/users", %{conn: conn} do
    conn = log_in_user(conn, member_user_fixture())
    assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, ~p"/admin/users")
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

    test "creates a member user tied to a department, with no password of their own yet", %{
      conn: conn
    } do
      department = department_fixture(%{name: "Finance Office"})
      {:ok, view, _html} = live(conn, ~p"/admin/users/new")

      html =
        view
        |> form("form",
          user: %{
            email: "finance-lead@example.com",
            role: "member",
            department_id: department.id
          }
        )
        |> render_submit()

      assert_patch(view, ~p"/admin/users")
      assert html =~ "invite email was sent" or render(view) =~ "invite email was sent"

      user = Accounts.get_user_by_email("finance-lead@example.com")
      assert user.role == "member"
      assert user.department_id == department.id
      assert user.hashed_password == nil

      assert Repo.get_by(UserToken, user_id: user.id, context: "invite")
    end

    test "creating a member without a department fails validation", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/users/new")

      html =
        view
        |> form("form", user: %{email: "nodept@example.com", role: "member"})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
      refute Accounts.get_user_by_email("nodept@example.com")
    end

    test "resending an invite issues a fresh token", %{conn: conn} do
      department = department_fixture(%{name: "Finance Office"})
      member = member_user_fixture(%{department: department, password: nil})

      {:ok, view, html} = live(conn, ~p"/admin/users")

      assert html =~ "Invite pending"

      view
      |> element("button[phx-value-id=\"#{member.id}\"]", "Resend invite")
      |> render_click()

      assert render(view) =~ "Invite resent"
      assert Repo.get_by(UserToken, user_id: member.id, context: "invite")
    end

    test "pre-fills the department when linked from a department's page", %{conn: conn} do
      department = department_fixture(%{name: "Finance Office"})
      {:ok, _view, html} = live(conn, ~p"/admin/users/new?department_id=#{department.id}")

      option =
        Regex.run(~r/<option[^>]*value="#{department.id}"[^>]*>Finance Office<\/option>/, html)

      assert option, "expected a <option> for department #{department.id}, got: #{html}"
      assert hd(option) =~ "selected"
    end

    test "can remove another user", %{conn: conn} do
      member = member_user_fixture()
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      view |> element("button", "Remove") |> render_click()

      refute Accounts.get_user_by_email(member.email)
      refute has_element?(view, "td", member.email)
    end

    test "cannot remove your own account", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/users")

      refute html =~ "Remove"
      refute has_element?(view, "button", "Remove")
    end
  end
end
