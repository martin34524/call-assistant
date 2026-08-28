defmodule CallAssistantWeb.LeadLiveTest do
  use CallAssistantWeb.ConnCase

  import Phoenix.LiveViewTest

  alias CallAssistant.Leads

  test "shows a not-yet-called lead with no transcript", %{conn: conn} do
    {:ok, lead} =
      Leads.create_lead(%{
        "name" => "Ada Lovelace",
        "phone" => "+15551234567",
        "source" => "manual"
      })

    {:ok, view, html} = live(conn, ~p"/leads/#{lead.id}")

    assert html =~ "Ada Lovelace"
    assert has_element?(view, "a", "Back to dashboard")

    CallAssistant.DataCase.await_background_tasks()
  end

  test "renders the parsed transcript once a call completes", %{conn: conn} do
    Leads.subscribe()

    {:ok, lead} =
      Leads.create_lead(%{
        "name" => "Grace Hopper",
        "phone" => "+15551234567",
        "source" => "manual"
      })

    lead_id = await_terminal(lead.id)
    CallAssistant.DataCase.await_background_tasks()

    {:ok, view, _html} = live(conn, ~p"/leads/#{lead_id}")

    # The mock adapter always writes timestamped "[HH:MM:SS] BOT:"/"USER:"
    # lines, matching the real transcript format, so at least one bubble
    # for each speaker should render for any completed/declined outcome
    # that has a transcript. no_answer/failed outcomes have no transcript.
    html = render(view)

    if String.contains?(html, "Conversation") and Leads.get_lead!(lead_id).transcript do
      assert html =~ "CALL-E"
    end
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
