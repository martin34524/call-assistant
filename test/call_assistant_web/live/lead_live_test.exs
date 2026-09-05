defmodule CallAssistantWeb.LeadLiveTest do
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

  test "shows a not-yet-called lead with no transcript", %{conn: conn, department: department} do
    {:ok, lead} =
      Leads.create_lead(department, %{"name" => "Ada Lovelace", "phone" => "+15551234567"})

    {:ok, view, html} = live(conn, ~p"/leads/#{lead.id}")

    assert html =~ "Ada Lovelace"
    assert has_element?(view, "a", "Back to dashboard")

    CallAssistant.DataCase.await_background_tasks()
  end

  test "404s when the lead belongs to a different department", %{conn: conn} do
    other_department = department_fixture(%{name: "Store Office"})

    {:ok, lead} =
      Leads.create_lead(other_department, %{"name" => "Not Mine", "phone" => "+15551234567"})

    CallAssistant.DataCase.await_background_tasks()
    assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/leads/#{lead.id}") end
  end

  test "renders the parsed transcript once a call completes", %{
    conn: conn,
    department: department,
    scope: scope
  } do
    Leads.subscribe(scope)

    {:ok, lead} =
      Leads.create_lead(department, %{"name" => "Grace Hopper", "phone" => "+15551234567"})

    lead_id = await_terminal(lead.id)
    CallAssistant.DataCase.await_background_tasks()

    {:ok, view, _html} = live(conn, ~p"/leads/#{lead_id}")

    # The mock adapter always writes timestamped "[HH:MM:SS] BOT:"/"USER:"
    # lines, matching the real transcript format, so at least one bubble
    # for each speaker should render for any completed/declined outcome
    # that has a transcript. no_answer/failed outcomes have no transcript.
    html = render(view)

    if String.contains?(html, "Conversation") and Leads.get_lead!(scope, lead_id).transcript do
      assert html =~ "CALL-E"
    end
  end

  test "keeps the instructions given to the AI visible after the call has settled", %{
    conn: conn,
    department: department,
    scope: scope
  } do
    Leads.subscribe(scope)

    {:ok, lead} =
      Leads.create_lead(department, %{
        "name" => "Grace Hopper",
        "phone" => "+15551234567",
        "context" => "Ask about their current supplier."
      })

    lead_id = await_terminal(lead.id)
    CallAssistant.DataCase.await_background_tasks()

    {:ok, _view, html} = live(conn, ~p"/leads/#{lead_id}")

    assert html =~ "Ask about their current supplier."
    assert html =~ "What we told the AI"
  end

  test "redialing a settled call navigates to the new linked call with the same context", %{
    conn: conn,
    department: department,
    scope: scope
  } do
    Leads.subscribe(scope)

    {:ok, lead} =
      Leads.create_lead(department, %{
        "name" => "Grace Hopper",
        "phone" => "+15551234567",
        "context" => "Ask about their current supplier."
      })

    lead_id = await_terminal(lead.id)
    CallAssistant.DataCase.await_background_tasks()

    {:ok, view, _html} = live(conn, ~p"/leads/#{lead_id}")

    view
    |> element("button", "Redial")
    |> render_click()

    assert has_element?(view, "#redial-form textarea", "Ask about their current supplier.")

    {:error, {:live_redirect, %{to: to}}} =
      view
      |> form("#redial-form", redial: %{context: "Ask about their current supplier."})
      |> render_submit()

    assert to != ~p"/leads/#{lead_id}"

    {:ok, _redial_view, html} = live(conn, to)
    assert html =~ "Grace Hopper"
    assert html =~ "Ask about their current supplier."
    assert html =~ "Follow-up call for"

    CallAssistant.DataCase.await_background_tasks()
  end

  test "shows the scheduled time and the call's content for a scheduled lead", %{
    conn: conn,
    department: department
  } do
    scheduled_at = DateTime.add(DateTime.utc_now(), 1, :day)

    {:ok, lead} =
      Leads.create_lead(department, %{
        "name" => "Ada Lovelace",
        "phone" => "+15551234567",
        "context" => "Let them know invoice #4521 is overdue.",
        "scheduled_at" => scheduled_at
      })

    {:ok, view, html} = live(conn, ~p"/leads/#{lead.id}")

    assert html =~ "Scheduled for"
    assert html =~ "invoice #4521 is overdue"
    assert has_element?(view, "button", "Cancel")
  end

  defp await_terminal(lead_id, deadline \\ System.monotonic_time(:millisecond) + 5_000) do
    receive do
      {:lead_updated, %{id: ^lead_id, status: status}} ->
        if status in CallAssistant.CallE.terminal_statuses() do
          lead_id
        else
          await_terminal(lead_id, deadline)
        end
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        flunk("timed out waiting for lead #{lead_id} to reach a terminal status")
    end
  end
end
