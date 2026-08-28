defmodule CallAssistant.Claude.Mock do
  @moduledoc """
  Deterministic classifier for dev/test - no network call. Picks an
  outcome by looking for a marker word in the lead's transcript/summary,
  so tests (and manual dev walkthroughs) can trigger each of the three
  real outcomes on demand instead of getting a random one:

    * transcript/summary mentions "ESCALATE_AUTO" -> needs_escalation,
      auto_handleable
    * mentions "ESCALATE" (without "_AUTO") -> needs_escalation, not
      auto_handleable (goes to the admin's review queue)
    * anything else -> no escalation

  Real calls placed through the mock `CallE` adapter never contain these
  markers, so ordinary demo traffic is unaffected.
  """

  @behaviour CallAssistant.Claude

  @impl true
  def classify_call(lead) do
    text = "#{lead.transcript} #{lead.summary}"

    cond do
      text =~ "ESCALATE_AUTO" ->
        {:ok,
         %{
           needs_escalation: true,
           reason: "The caller asked for something only the admin's office can approve.",
           auto_handleable: true,
           suggested_goal:
             "Follow up with #{lead.name} to schedule a meeting about what they raised on the " <>
               "previous call, based on this summary: #{lead.summary}"
         }}

      text =~ "ESCALATE" ->
        {:ok,
         %{
           needs_escalation: true,
           reason: "The caller asked to speak with someone from the admin's office.",
           auto_handleable: false,
           suggested_goal: "Follow up with #{lead.name} about their earlier request."
         }}

      true ->
        {:ok,
         %{needs_escalation: false, reason: nil, auto_handleable: false, suggested_goal: nil}}
    end
  end
end
