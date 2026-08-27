defmodule CallAssistantWeb.LeadsLiveTest do
  use CallAssistantWeb.ConnCase

  import Phoenix.LiveViewTest

  alias CallAssistant.Leads

  test "renders empty state with no leads", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Speed-to-Lead"
    assert html =~ "No leads yet"
  end

  test "submitting the form creates a lead and shows it calling live", %{conn: conn} do
    Leads.subscribe()
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

    assert html =~ "Qualified" or html =~ "Not interested" or html =~ "No answer" or
             html =~ "Failed"

    assert Leads.get_lead!(lead_id).status in ~w(qualified disqualified no_answer failed)
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

    if status in ~w(qualified disqualified no_answer failed) do
      id
    else
      assert_receive_terminal_lead_id()
    end
  end
end
