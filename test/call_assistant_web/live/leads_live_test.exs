defmodule CallAssistantWeb.LeadsLiveTest do
  use CallAssistantWeb.ConnCase

  import Phoenix.LiveViewTest
  import CallAssistant.AccountsFixtures

  alias CallAssistant.Leads

  setup %{conn: conn} do
    department = department_fixture(%{name: "Finance Office"})
    user = member_user_fixture(%{department: department})

    %{
      conn: log_in_user(conn, user),
      department: department,
      scope: CallAssistant.Accounts.Scope.for_user(user)
    }
  end

  test "redirects to /users/log-in when not authenticated" do
    conn = Phoenix.ConnTest.build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/")
  end

  test "redirects an admin to /admin instead of the department dashboard" do
    conn = Phoenix.ConnTest.build_conn() |> log_in_user(admin_user_fixture())
    assert {:error, {:redirect, %{to: "/admin"}}} = live(conn, ~p"/")
  end

  test "renders empty state with no leads", %{conn: conn, department: department} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ department.name
    assert html =~ "No leads yet"
  end

  test "submitting the form creates a lead scoped to the user's department and shows it calling live",
       %{conn: conn, scope: scope} do
    Leads.subscribe(scope)
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("form", lead: %{name: "Ada Lovelace", phone: "+15551234567", source: "Website form"})
    |> render_submit()

    assert has_element?(view, "td", "Ada Lovelace")

    # The Qualifier runs the (test-configured, fast) mock call flow in a
    # background task and broadcasts each status change over PubSub. Wait
    # for the terminal broadcast, the same signal the LiveView itself acts
    # on, then confirm the dashboard reflects it without a page reload.
    lead_id = assert_receive_terminal_lead_id()

    html = render(view)

    assert html =~ "Completed" or html =~ "Declined" or html =~ "No answer" or html =~ "Failed"

    assert Leads.get_lead!(scope, lead_id).status in CallAssistant.CallE.terminal_statuses()
    CallAssistant.DataCase.await_background_tasks()
  end

  test "never shows another department's leads", %{conn: conn, department: department} do
    other_department = department_fixture(%{name: "Store Office"})

    {:ok, _other_lead} =
      Leads.create_lead(other_department, %{"name" => "Not Mine", "phone" => "+15551234567"})

    {:ok, _own_lead} =
      Leads.create_lead(department, %{"name" => "Mine", "phone" => "+15551234567"})

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "td", "Mine")
    refute has_element?(view, "td", "Not Mine")
    CallAssistant.DataCase.await_background_tasks()
  end

  test "rejects an invalid phone number", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html =
      view
      |> form("form", lead: %{name: "Ada Lovelace", phone: "bad", source: "Website form"})
      |> render_submit()

    assert html =~ "must be a valid phone number"
  end

  defp assert_receive_terminal_lead_id do
    assert_receive {:lead_updated, %{id: id, status: status}}, 5_000

    if status in CallAssistant.CallE.terminal_statuses() do
      id
    else
      assert_receive_terminal_lead_id()
    end
  end
end
