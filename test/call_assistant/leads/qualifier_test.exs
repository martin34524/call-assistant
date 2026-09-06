defmodule CallAssistant.Leads.QualifierTest do
  # Mutates the global :call_e_client app env for the duration of this
  # file (see setup/1 below) - must not run concurrently with other tests
  # that place calls (which read that same config via CallE.client/0).
  use CallAssistant.DataCase, async: false

  import CallAssistant.AccountsFixtures

  alias CallAssistant.Leads
  alias CallAssistant.Leads.Qualifier

  # The Mock adapter (config/test.exs's default) never fails plan_call or
  # run_call, so it can't exercise CallE.Cli's call_started/recovery_id
  # handling (see CallAssistant.CallE.Cli's call_failure/1). This double
  # lets each test dictate exactly what each stage returns via the test
  # process's own dictionary - safe because Qualifier.run/1 is called
  # directly below (not through Qualifier.start/1's Task), so it's always
  # the test process itself calling into this module.
  defmodule FailingClient do
    @moduledoc false
    @behaviour CallAssistant.CallE

    def plan_call(_params) do
      Process.get(:plan_call_result) ||
        {:ok,
         %{
           plan_id: "plan_1",
           ready_to_run: true,
           confirm_token: "token_1",
           clarifying_questions: []
         }}
    end

    def run_call(_params) do
      Process.get(:run_call_result) || {:ok, %{call_run_id: "run_1", status: "in_progress"}}
    end

    def get_call_run(_params) do
      Process.get(:get_call_run_result) ||
        {:ok,
         %{
           status: "in_progress",
           message: nil,
           transcript: nil,
           summary: nil,
           task_completed: nil
         }}
    end
  end

  setup do
    previous = Application.get_env(:call_assistant, :call_e_client)
    Application.put_env(:call_assistant, :call_e_client, FailingClient)
    on_exit(fn -> Application.put_env(:call_assistant, :call_e_client, previous) end)

    department = department_fixture(%{name: "Finance Office"})
    %{department: department, scope: member_scope_fixture(%{department: department})}
  end

  # scheduled_at in the future stops Leads.create_lead/2 from also firing
  # its own automatic Qualifier.start/1 (a separate Task, with its own
  # process dictionary the Process.put/2 calls below can't reach) - each
  # test calls Qualifier.run/1 itself, directly and synchronously, once
  # FailingClient is primed.
  defp new_lead(department) do
    {:ok, lead} =
      Leads.create_lead(department, %{
        "name" => "Ada Lovelace",
        "phone" => "+15551234567",
        "scheduled_at" => DateTime.add(DateTime.utc_now(), 1, :hour)
      })

    lead
  end

  describe "a plan_call failure" do
    test "marks the lead failed with a clean message when CALL-E confirms nothing started", %{
      department: department,
      scope: scope
    } do
      Process.put(
        :plan_call_result,
        {:error,
         {:call_failure,
          %{message: "plan_call failed: fetch failed", call_uncertain: false, recovery_id: nil}}}
      )

      lead = new_lead(department)
      assert {:ok, failed} = Qualifier.run(lead)

      assert failed.status == "failed"
      assert failed.error == "plan_call failed: fetch failed"
      refute failed.call_uncertain
      refute failed.recovery_id
      refute Leads.get_lead!(scope, lead.id).call_uncertain
    end
  end

  describe "a run_call failure" do
    test "marks the lead failed with call_uncertain and stores the recovery_id", %{
      department: department,
      scope: scope
    } do
      Process.put(
        :run_call_result,
        {:error,
         {:call_failure,
          %{
            message: "run_call failed: fetch failed",
            call_uncertain: true,
            recovery_id: "PKCarVFXk7xdUh3cbwU8qJRD"
          }}}
      )

      lead = new_lead(department)
      assert {:ok, failed} = Qualifier.run(lead)

      assert failed.status == "failed"
      assert failed.call_uncertain
      assert failed.recovery_id == "PKCarVFXk7xdUh3cbwU8qJRD"
      assert Leads.get_lead!(scope, lead.id).call_uncertain
    end
  end

  describe "a get_call_run poll timeout" do
    test "marks the lead failed with call_uncertain, since a real call was already placed", %{
      department: department
    } do
      # FailingClient's default get_call_run/1 stays "in_progress" forever,
      # so poll_until_done/3 loops until the (test-config-shortened, see
      # config/test.exs's qualifier_poll_timeout_ms) timeout fires.
      lead = new_lead(department)
      assert {:ok, failed} = Qualifier.run(lead)

      assert failed.status == "failed"
      assert failed.error == "timed out waiting for call result"
      assert failed.call_uncertain
    end
  end

  describe "resume/2" do
    # A lead already sitting in "needs_clarification" (as run/1 would have
    # left it) - resume/2 is the only caller that ever passes a plan_id
    # back into plan_call, so it's exercised directly here rather than via
    # a full run/1 round trip.
    defp clarification_needed_lead(department) do
      lead = new_lead(department)
      {:ok, lead} = Leads.update_lead(lead, %{status: "needs_clarification", plan_id: "plan_1"})
      lead
    end

    test "an answer that resolves the plan proceeds through run_call to a terminal outcome", %{
      department: department
    } do
      Process.put(
        :get_call_run_result,
        {:ok,
         %{
           status: "completed",
           message: nil,
           transcript: nil,
           summary: "resumed and completed",
           task_completed: true
         }}
      )

      lead = clarification_needed_lead(department)

      assert {:ok, done} = Qualifier.resume(lead, "Use +15559990000, English.")

      assert done.status == "completed"
      assert done.summary == "resumed and completed"
    end

    test "an answer that's still ready_to_run: false lands back on needs_clarification", %{
      department: department
    } do
      Process.put(
        :plan_call_result,
        {:ok,
         %{
           plan_id: "plan_1",
           ready_to_run: false,
           confirm_token: nil,
           clarifying_questions: ["Which number - the one you just gave is still ambiguous."]
         }}
      )

      lead = clarification_needed_lead(department)

      assert {:ok, still_needs_info} = Qualifier.resume(lead, "call the usual one")

      assert still_needs_info.status == "needs_clarification"
      assert still_needs_info.summary =~ "still ambiguous"
    end
  end
end
