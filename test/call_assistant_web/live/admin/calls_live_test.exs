defmodule CallAssistantWeb.Admin.CallsLiveTest do
  use CallAssistantWeb.ConnCase

  import Phoenix.LiveViewTest
  import CallAssistant.AccountsFixtures

  alias CallAssistant.Leads

  test "a member is redirected away from /admin/calls", %{conn: conn} do
    conn = log_in_user(conn, member_user_fixture())
    assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, ~p"/admin/calls")
  end

  describe "as an admin" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, admin_user_fixture())}
    end

    test "shows calls from every department", %{conn: conn} do
      finance = department_fixture(%{name: "Finance Office"})
      store = department_fixture(%{name: "Store Office"})

      {:ok, _a} =
        Leads.create_lead(finance, %{"name" => "Finance Lead", "phone" => "+15551234567"})

      {:ok, _b} = Leads.create_lead(store, %{"name" => "Store Lead", "phone" => "+15551234567"})

      {:ok, view, _html} = live(conn, ~p"/admin/calls")

      assert has_element?(view, "td", "Finance Lead")
      assert has_element?(view, "td", "Store Lead")
      CallAssistant.DataCase.await_background_tasks()
    end

    test "can place a call by picking a department directly on this page", %{conn: conn} do
      department = department_fixture(%{name: "Finance Office"})
      {:ok, view, _html} = live(conn, ~p"/admin/calls")

      view
      |> form("#new-call-form",
        lead: %{department_id: department.id, name: "Ada Lovelace", phone: "+15551234567"}
      )
      |> render_submit()

      assert has_element?(view, "td", "Ada Lovelace")
      assert [lead] = Leads.list_leads_for_department(department.id)
      assert lead.name == "Ada Lovelace"
      CallAssistant.DataCase.await_background_tasks()
    end

    test "department is optional - defaults to the admin's own department", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/calls")

      view
      |> form("#new-call-form", lead: %{name: "Ada Lovelace", phone: "+15551234567"})
      |> render_submit()

      assert has_element?(view, "td", "Ada Lovelace")
      admin_department = CallAssistant.Departments.admin_department()
      assert [lead] = Leads.list_leads_for_department(admin_department.id)
      assert lead.name == "Ada Lovelace"
      CallAssistant.DataCase.await_background_tasks()
    end

    test "voice command: matches an existing contact across departments and places the call in Admin",
         %{conn: conn} do
      finance = department_fixture(%{name: "Finance Office"})

      {:ok, _existing} =
        Leads.create_lead(finance, %{"name" => "Jane Doe", "phone" => "+15559876543"})

      CallAssistant.DataCase.await_background_tasks()

      {:ok, view, _html} = live(conn, ~p"/admin/calls")

      view |> element("[data-voice-mic]") |> render_click()
      render_hook(view, "voice_transcript", %{"text" => "call Jane Doe"})

      html = render(view)
      assert html =~ "Jane Doe"
      assert html =~ "+15559876543"

      render_hook(view, "voice_transcript", %{"text" => "just a check-in"})
      render_hook(view, "voice_transcript", %{"text" => "yes"})

      assert render(view) =~ "Calling Jane Doe now"

      admin_department = CallAssistant.Departments.admin_department()
      assert [lead] = Leads.list_leads_for_department(admin_department.id)
      assert lead.name == "Jane Doe"

      CallAssistant.DataCase.await_background_tasks()
    end

    test "voice command: no contact on file asks for a phone number", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/calls")

      view |> element("[data-voice-mic]") |> render_click()
      render_hook(view, "voice_transcript", %{"text" => "call Grace Hopper"})

      assert render(view) =~ "phone number"
    end

    test "search filters the calls table by name or phone", %{conn: conn} do
      finance = department_fixture(%{name: "Finance Office"})

      {:ok, _a} =
        Leads.create_lead(finance, %{"name" => "Ada Lovelace", "phone" => "+15551234567"})

      {:ok, _b} =
        Leads.create_lead(finance, %{"name" => "Grace Hopper", "phone" => "+15559998888"})

      CallAssistant.DataCase.await_background_tasks()

      {:ok, view, _html} = live(conn, ~p"/admin/calls")

      html =
        view
        |> form("#search-calls-form", %{"q" => "grace"})
        |> render_change()

      assert html =~ "Grace Hopper"
      refute html =~ "Ada Lovelace"
    end

    test "scheduling a call for later leaves it scheduled instead of placing it immediately", %{
      conn: conn
    } do
      department = department_fixture(%{name: "Finance Office"})
      {:ok, view, _html} = live(conn, ~p"/admin/calls")

      html =
        view
        |> form("#new-call-form",
          lead: %{
            department_id: department.id,
            name: "Ada Lovelace",
            phone: "+15551234567",
            scheduled_at: datetime_local_value()
          }
        )
        |> render_submit()

      assert html =~ "is scheduled for"

      assert [lead] = Leads.list_leads_for_department(department.id)
      assert lead.status == "scheduled"
      assert lead.call_run_id == nil
    end
  end

  defp datetime_local_value do
    DateTime.utc_now()
    |> DateTime.add(1, :day)
    |> DateTime.to_naive()
    |> NaiveDateTime.to_iso8601()
    |> String.slice(0, 16)
  end
end
