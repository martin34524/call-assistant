defmodule CallAssistant.Claude.Prompt do
  @moduledoc false
  # Shared prompt text and response validation for the real classifier
  # adapters (CallAssistant.Claude.Live, CallAssistant.Claude.Gemini) -
  # they only differ in transport (Anthropic vs Google's API), not in what
  # they ask for or how the answer is checked.

  @system_prompt """
  You are a call-triage assistant for a business phone system. You'll be given the goal of a phone call an AI agent (CALL-E) just placed on behalf of a company, plus the call's summary and full transcript. Decide whether this call surfaced something that specifically needs the company's admin/management team to review or act on - e.g. the caller asked for something outside a department's authority, a complaint, an unusual or high-value request, something the department can't approve on its own. Routine, successful, or simply unanswered/declined calls do not need escalation.

  Respond with ONLY a single JSON object, no other text before or after it, matching exactly this shape:
  {"needs_escalation": boolean, "reason": string or null, "auto_handleable": boolean, "suggested_goal": string or null}

  - needs_escalation: true only when the call clearly surfaced something for admin.
  - reason: one sentence explaining why, only when needs_escalation is true, else null.
  - auto_handleable: true only when needs_escalation is true AND the transcript gives you clearly enough information to draft a specific, well-informed follow-up call goal without a human needing to add missing context first. Default to false whenever you're not confident - a human should stay in the loop unless the situation is unambiguous.
  - suggested_goal: when needs_escalation is true, a complete instruction for a follow-up call to this same person (what to say, what to find out or accomplish), written using what you learned from the transcript, in the same style as a normal call goal. null when needs_escalation is false.
  """

  def system_prompt, do: @system_prompt

  def user_message(lead) do
    """
    Call goal: #{lead.goal}

    Call summary: #{lead.summary || "(none)"}

    Full transcript:
    #{lead.transcript || "(none)"}
    """
  end

  def validate(%{"needs_escalation" => needs_escalation} = decoded)
      when is_boolean(needs_escalation) do
    {:ok,
     %{
       needs_escalation: needs_escalation,
       reason: Map.get(decoded, "reason"),
       auto_handleable: Map.get(decoded, "auto_handleable", false) == true,
       suggested_goal: Map.get(decoded, "suggested_goal")
     }}
  end

  def validate(other), do: {:error, {:unexpected_response, other}}
end
