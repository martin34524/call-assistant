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
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/dashboard")
  end

  test "redirects an admin to /admin instead of the department dashboard" do
    conn = Phoenix.ConnTest.build_conn() |> log_in_user(admin_user_fixture())
    assert {:error, {:redirect, %{to: "/admin"}}} = live(conn, ~p"/dashboard")
  end

  test "renders empty state with no leads", %{conn: conn, department: department} do
    {:ok, _view, html} = live(conn, ~p"/dashboard")
    assert html =~ department.name
    assert html =~ "No leads yet"
  end

  test "submitting the form creates a lead scoped to the user's department and shows it calling live",
       %{conn: conn, scope: scope} do
    Leads.subscribe(scope)
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    view
    |> form("#new-lead-form",
      lead: %{name: "Ada Lovelace", phone: "+15551234567", source: "Website form"}
    )
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

    {:ok, view, _html} = live(conn, ~p"/dashboard")

    assert has_element?(view, "td", "Mine")
    refute has_element?(view, "td", "Not Mine")
    CallAssistant.DataCase.await_background_tasks()
  end

  test "cancelling an in-flight call marks it cancelled and dismisses the calling flash", %{
    conn: conn,
    scope: scope
  } do
    Leads.subscribe(scope)
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    view
    |> form("#new-lead-form",
      lead: %{name: "Ada Lovelace", phone: "+15551234567", source: "Website form"}
    )
    |> render_submit()

    assert render(view) =~ "Calling Ada Lovelace now"

    assert_receive {:lead_updated, %{id: lead_id, status: "in_progress"}}, 5_000

    view
    |> element("#lead-#{lead_id} button", "Cancel")
    |> render_click()

    html = render(view)
    assert html =~ "Cancelled"
    refute html =~ "Calling Ada Lovelace now"

    assert Leads.get_lead!(scope, lead_id).status == "cancelled"
    CallAssistant.DataCase.await_background_tasks()
  end

  test "rejects an invalid phone number", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    html =
      view
      |> form("#new-lead-form",
        lead: %{name: "Ada Lovelace", phone: "bad", source: "Website form"}
      )
      |> render_submit()

    assert html =~ "must be a valid phone number"
  end

  test "scheduling a call for later leaves it scheduled with no call placed yet", %{
    conn: conn,
    scope: scope
  } do
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    html =
      view
      |> form("#new-lead-form",
        lead: %{name: "Ada Lovelace", phone: "+15551234567", scheduled_at: datetime_local_value()}
      )
      |> render_submit()

    assert html =~ "is scheduled for"

    assert [lead] = Leads.list_leads(scope)
    assert lead.status == "scheduled"
    assert lead.scheduled_at
    assert lead.call_run_id == nil
  end

  test "cancelling a scheduled call before it fires marks it cancelled", %{
    conn: conn,
    scope: scope
  } do
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    view
    |> form("#new-lead-form",
      lead: %{name: "Ada Lovelace", phone: "+15551234567", scheduled_at: datetime_local_value()}
    )
    |> render_submit()

    assert [lead] = Leads.list_leads(scope)

    view
    |> element("#lead-#{lead.id} button", "Cancel")
    |> render_click()

    html = render(view)
    assert html =~ "Cancelled"

    assert Leads.get_lead!(scope, lead.id).status == "cancelled"
  end

  defp datetime_local_value do
    DateTime.utc_now()
    |> DateTime.add(1, :day)
    |> DateTime.to_naive()
    |> NaiveDateTime.to_iso8601()
    |> String.slice(0, 16)
  end

  test "search filters the calls table by name or phone", %{conn: conn, department: department} do
    {:ok, _a} =
      Leads.create_lead(department, %{"name" => "Ada Lovelace", "phone" => "+15551234567"})

    {:ok, _b} =
      Leads.create_lead(department, %{"name" => "Grace Hopper", "phone" => "+15559998888"})

    CallAssistant.DataCase.await_background_tasks()

    {:ok, view, _html} = live(conn, ~p"/dashboard")

    assert has_element?(view, "td", "Ada Lovelace")
    assert has_element?(view, "td", "Grace Hopper")

    html =
      view
      |> form("#search-leads-form", %{"q" => "grace"})
      |> render_change()

    assert html =~ "Grace Hopper"
    refute html =~ "Ada Lovelace"

    html =
      view
      |> form("#search-leads-form", %{"q" => "9998888"})
      |> render_change()

    assert html =~ "Grace Hopper"

    html =
      view
      |> form("#search-leads-form", %{"q" => "nobody"})
      |> render_change()

    assert html =~ "No calls match"
  end

  test "shows a live call panel for an in-flight lead, with its real fields only", %{
    conn: conn,
    department: department
  } do
    # Set the lead to "in_progress" directly rather than racing the mock
    # Qualifier's own (test-tuned, very fast) poll loop past that status
    # before the assertions below run.
    {:ok, lead} =
      Leads.create_lead(department, %{"name" => "Ada Lovelace", "phone" => "+15551234567"})

    CallAssistant.DataCase.await_background_tasks()

    # The background Qualifier task already ran (and left a transcript,
    # since the mock outcome is random) by the time await_background_tasks
    # returns - clear that back out so this genuinely represents a call
    # that's still in flight, not a completed one with its status faked.
    {:ok, _lead} =
      Leads.update_lead(lead, %{
        status: "in_progress",
        status_message: "Ringing…",
        transcript: nil,
        summary: nil,
        task_completed: nil
      })

    {:ok, _view, html} = live(conn, ~p"/dashboard")

    assert html =~ "Live call"
    assert html =~ "Ada Lovelace"
    assert html =~ "status:"
    assert html =~ "in_progress"
    refute html =~ "intent:"
    refute html =~ "sentiment:"
  end

  describe "voice command" do
    # No real browser/mic in tests - render_hook simulates exactly what the
    # colocated hook's pushEvent calls send, so this exercises the full
    # server-side state machine (including a real Leads.create_lead/2 call
    # on confirm) without needing SpeechRecognition itself.

    test "happy path: single contact match -> context -> confirm places the call", %{
      conn: conn,
      department: department,
      scope: scope
    } do
      {:ok, _existing} =
        Leads.create_lead(department, %{"name" => "Jane Doe", "phone" => "+15559876543"})

      CallAssistant.DataCase.await_background_tasks()
      Leads.subscribe(scope)

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view |> element("[data-voice-mic]") |> render_click()
      render_hook(view, "voice_transcript", %{"text" => "please call Jane Doe"})

      assert render(view) =~ "What&#39;s the call about?" or render(view) =~ "call about"

      render_hook(view, "voice_transcript", %{"text" => "the invoice is overdue"})

      html = render(view)
      assert html =~ "Jane Doe"
      assert html =~ "+15559876543"
      assert html =~ "invoice is overdue"

      render_hook(view, "voice_transcript", %{"text" => "yes"})

      assert render(view) =~ "Calling Jane Doe now"

      assert Enum.any?(
               Leads.list_leads(scope),
               &(&1.name == "Jane Doe" and is_binary(&1.context) and &1.context =~ "overdue")
             )

      CallAssistant.DataCase.await_background_tasks()
    end

    test "no contact on file asks for a phone number before context", %{
      conn: conn,
      scope: scope
    } do
      Leads.subscribe(scope)
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view |> element("[data-voice-mic]") |> render_click()
      render_hook(view, "voice_transcript", %{"text" => "call Grace Hopper"})

      assert render(view) =~ "phone number"

      render_hook(view, "voice_transcript", %{"text" => "it's 555 222 3333"})
      assert render(view) =~ "call about"

      render_hook(view, "voice_transcript", %{"text" => "introduce ourselves"})
      html = render(view)
      assert html =~ "Grace Hopper"
      assert html =~ "555"

      render_hook(view, "voice_transcript", %{"text" => "yes please"})
      assert render(view) =~ "Calling Grace Hopper now"

      assert Enum.any?(Leads.list_leads(scope), &(&1.name == "Grace Hopper"))
      CallAssistant.DataCase.await_background_tasks()
    end

    test "multiple distinct numbers for a name shows a disambiguation list", %{
      conn: conn,
      department: department,
      scope: scope
    } do
      {:ok, _a} =
        Leads.create_lead(department, %{"name" => "Jane Doe", "phone" => "+15551110001"})

      {:ok, _b} =
        Leads.create_lead(department, %{"name" => "Jane Doe", "phone" => "+15551110002"})

      CallAssistant.DataCase.await_background_tasks()
      Leads.subscribe(scope)

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view |> element("[data-voice-mic]") |> render_click()
      render_hook(view, "voice_transcript", %{"text" => "call Jane Doe"})

      html = render(view)
      assert html =~ "+15551110001"
      assert html =~ "+15551110002"

      view
      |> element("button[phx-value-index=\"0\"]")
      |> render_click()

      assert render(view) =~ "call about"

      render_hook(view, "voice_transcript", %{"text" => "checking in"})
      render_hook(view, "voice_transcript", %{"text" => "yes"})

      assert render(view) =~ "Calling Jane Doe now"
      CallAssistant.DataCase.await_background_tasks()
    end

    test "a spoken \"no\" at the confirm step cancels without placing a call", %{
      conn: conn,
      department: department,
      scope: scope
    } do
      {:ok, _existing} =
        Leads.create_lead(department, %{"name" => "Jane Doe", "phone" => "+15559876543"})

      CallAssistant.DataCase.await_background_tasks()

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view |> element("[data-voice-mic]") |> render_click()
      render_hook(view, "voice_transcript", %{"text" => "call Jane Doe"})
      render_hook(view, "voice_transcript", %{"text" => "just checking in"})
      render_hook(view, "voice_transcript", %{"text" => "no, cancel that"})

      refute render(view) =~ "Calling Jane Doe now"
      refute Enum.any?(Leads.list_leads(scope), &(&1.name == "Jane Doe" and &1.context))
    end

    test "clicking Cancel mid-flow resets to idle", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view |> element("[data-voice-mic]") |> render_click()
      render_hook(view, "voice_transcript", %{"text" => "call Nobody Here"})
      assert render(view) =~ "phone number"

      view |> element("button", "Cancel") |> render_click()
      assert render(view) =~ "Place a call by voice"
    end

    test "a recognition error shows a friendly message and resets", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view |> element("[data-voice-mic]") |> render_click()
      render_hook(view, "voice_recognition_error", %{"reason" => "not-allowed"})

      assert render(view) =~ "Microphone access was blocked"
      assert render(view) =~ "Place a call by voice"
    end
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
