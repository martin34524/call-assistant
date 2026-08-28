defmodule CallAssistant.Claude.Mock do
  @moduledoc """
  Deterministic classifier for dev/test - no network call. Picks an
  outcome by looking for marker words in the lead's transcript/summary,
  so tests (and manual dev walkthroughs) can trigger each real outcome on
  demand instead of getting a random one:

    * transcript/summary mentions "ESCALATE_AUTO" -> needs_escalation,
      auto_handleable
    * mentions "ESCALATE" (without "_AUTO") -> needs_escalation, not
      auto_handleable (goes to the admin's review queue)
    * mentions "ESCALATE_TO[Department Name]" (combinable with either of
      the above; brackets since transcript and summary get joined with a
      plain space, not a newline, so an unbounded marker would swallow
      everything after it) -> suggested_department is that name verbatim,
      exactly as CallAssistant.Leads.Escalation would resolve a real
      classifier's answer - lets tests exercise "this Admin-line call
      actually needs Finance" without a real LLM call
    * anything else -> no escalation

  Real calls placed through the mock `CallE` adapter never contain these
  markers, so ordinary demo traffic is unaffected.
  """

  @behaviour CallAssistant.Claude

  @impl true
  def classify_call(lead) do
    text = "#{lead.transcript} #{lead.summary}"
    department = suggested_department(text)

    cond do
      text =~ "ESCALATE_AUTO" ->
        {:ok,
         %{
           needs_escalation: true,
           reason: "The caller asked for something only the admin's office can approve.",
           auto_handleable: true,
           suggested_goal:
             "Follow up with #{lead.name} to schedule a meeting about what they raised on the " <>
               "previous call, based on this summary: #{lead.summary}",
           suggested_department: department
         }}

      text =~ "ESCALATE" ->
        {:ok,
         %{
           needs_escalation: true,
           reason: "The caller asked to speak with someone from the admin's office.",
           auto_handleable: false,
           suggested_goal: "Follow up with #{lead.name} about their earlier request.",
           suggested_department: department
         }}

      true ->
        {:ok,
         %{
           needs_escalation: false,
           reason: nil,
           auto_handleable: false,
           suggested_goal: nil,
           suggested_department: nil
         }}
    end
  end

  defp suggested_department(text) do
    case Regex.run(~r/ESCALATE_TO\[([^\]]+)\]/, text) do
      [_, name] -> String.trim(name)
      nil -> nil
    end
  end
end
