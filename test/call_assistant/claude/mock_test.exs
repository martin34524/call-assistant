defmodule CallAssistant.Claude.MockTest do
  use ExUnit.Case, async: true

  alias CallAssistant.Claude.Mock
  alias CallAssistant.Leads.Lead

  test "no marker in transcript/summary -> no escalation" do
    lead = %Lead{name: "Ada", transcript: "just a normal chat", summary: "Nothing unusual."}

    assert {:ok,
            %{
              needs_escalation: false,
              auto_handleable: false,
              suggested_goal: nil,
              suggested_department: nil
            }} = Mock.classify_call(lead)
  end

  test "\"ESCALATE\" marker -> needs escalation, not auto-handleable" do
    lead = %Lead{
      name: "Ada",
      transcript: "USER: I need to speak to someone from ESCALATE please.",
      summary: "Caller asked for admin's office."
    }

    assert {:ok,
            %{
              needs_escalation: true,
              auto_handleable: false,
              reason: reason,
              suggested_goal: goal
            }} =
             Mock.classify_call(lead)

    assert reason =~ "admin's office"
    assert goal =~ "Ada"
  end

  test "\"ESCALATE_AUTO\" marker -> needs escalation and is auto-handleable" do
    lead = %Lead{
      name: "Ada",
      transcript: "USER: please just handle this yourself, ESCALATE_AUTO",
      summary: "Caller wants a meeting scheduled."
    }

    assert {:ok,
            %{needs_escalation: true, auto_handleable: true, reason: reason, suggested_goal: goal}} =
             Mock.classify_call(lead)

    assert reason =~ "approve"
    assert goal =~ "Ada"
    assert goal =~ lead.summary
  end

  test "\"ESCALATE_TO:<name>\" marker sets suggested_department, combinable with either marker" do
    lead = %Lead{
      name: "Ada",
      transcript: "USER: I actually need Finance for this. ESCALATE_TO[Finance Office]",
      summary: "Wrong department, needs Finance."
    }

    assert {:ok, %{needs_escalation: true, suggested_department: "Finance Office"}} =
             Mock.classify_call(lead)
  end

  test "no \"ESCALATE_TO\" marker -> suggested_department is nil even when escalating" do
    lead = %Lead{
      name: "Ada",
      transcript: "USER: I need ESCALATE_AUTO handling.",
      summary: "General admin matter."
    }

    assert {:ok, %{suggested_department: nil}} = Mock.classify_call(lead)
  end
end
