defmodule CallAssistantWeb.MarketingLiveTest do
  use CallAssistantWeb.ConnCase

  import Phoenix.LiveViewTest
  import CallAssistant.AccountsFixtures

  test "renders the marketing page for a logged-out visitor", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Speed-to-Lead"
    assert html =~ "Log in"
    refute html =~ "Overview"
  end

  test "redirects an authenticated member straight to /dashboard", %{conn: conn} do
    conn = log_in_user(conn, member_user_fixture())
    assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, ~p"/")
  end

  test "redirects an authenticated admin straight to /admin", %{conn: conn} do
    conn = log_in_user(conn, admin_user_fixture())
    assert {:error, {:redirect, %{to: "/admin"}}} = live(conn, ~p"/")
  end
end
