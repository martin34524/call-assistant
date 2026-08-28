defmodule CallAssistant.Claude.Live do
  @moduledoc """
  Real classifier: one call to the Claude API (`claude-opus-5`) per
  completed lead, asking it to read the call's goal/transcript/summary
  and decide whether it needs an admin's attention.

  Elixir has no official Anthropic SDK, so this is raw HTTP via `Req`
  (already a dependency, used the same way for CALL-E) - the pattern the
  `claude-api` skill itself recommends for unsupported languages.

  Configure via:

      config :call_assistant, :anthropic_api_key,
        System.get_env("ANTHROPIC_API_KEY")
  """

  @behaviour CallAssistant.Claude

  require Logger

  @endpoint "https://api.anthropic.com/v1/messages"
  @model "claude-opus-5"

  @system_prompt """
  You are a call-triage assistant for a business phone system. You'll be given the goal of a phone call an AI agent (CALL-E) just placed on behalf of a company, plus the call's summary and full transcript. Decide whether this call surfaced something that specifically needs the company's admin/management team to review or act on - e.g. the caller asked for something outside a department's authority, a complaint, an unusual or high-value request, something the department can't approve on its own. Routine, successful, or simply unanswered/declined calls do not need escalation.

  Respond with ONLY a single JSON object, no other text before or after it, matching exactly this shape:
  {"needs_escalation": boolean, "reason": string or null, "auto_handleable": boolean, "suggested_goal": string or null}

  - needs_escalation: true only when the call clearly surfaced something for admin.
  - reason: one sentence explaining why, only when needs_escalation is true, else null.
  - auto_handleable: true only when needs_escalation is true AND the transcript gives you clearly enough information to draft a specific, well-informed follow-up call goal without a human needing to add missing context first. Default to false whenever you're not confident - a human should stay in the loop unless the situation is unambiguous.
  - suggested_goal: when needs_escalation is true, a complete instruction for a follow-up call to this same person (what to say, what to find out or accomplish), written using what you learned from the transcript, in the same style as a normal call goal. null when needs_escalation is false.
  """

  @impl true
  def classify_call(lead) do
    api_key = Application.get_env(:call_assistant, :anthropic_api_key)

    if is_nil(api_key) or api_key == "" do
      {:error, :not_configured}
    else
      request(api_key, lead)
    end
  end

  defp request(api_key, lead) do
    body = %{
      model: @model,
      max_tokens: 1024,
      system: @system_prompt,
      messages: [%{role: "user", content: user_message(lead)}]
    }

    case Req.post(@endpoint,
           headers: [
             {"x-api-key", api_key},
             {"anthropic-version", "2023-06-01"}
           ],
           json: body,
           receive_timeout: 30_000
         ) do
      {:ok, %Req.Response{status: 200, body: resp_body}} ->
        parse_response(resp_body)

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        Logger.warning("Claude API error #{status}: #{inspect(resp_body)}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.warning("Claude API request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp user_message(lead) do
    """
    Call goal: #{lead.goal}

    Call summary: #{lead.summary || "(none)"}

    Full transcript:
    #{lead.transcript || "(none)"}
    """
  end

  defp parse_response(%{"content" => content}) do
    with %{"text" => text} <- Enum.find(content, &(&1["type"] == "text")),
         {:ok, decoded} <- Jason.decode(String.trim(text)),
         {:ok, classification} <- validate(decoded) do
      {:ok, classification}
    else
      nil -> {:error, {:unexpected_response, "no text block in response"}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_response(other), do: {:error, {:unexpected_response, other}}

  defp validate(%{"needs_escalation" => needs_escalation} = decoded)
       when is_boolean(needs_escalation) do
    {:ok,
     %{
       needs_escalation: needs_escalation,
       reason: Map.get(decoded, "reason"),
       auto_handleable: Map.get(decoded, "auto_handleable", false) == true,
       suggested_goal: Map.get(decoded, "suggested_goal")
     }}
  end

  defp validate(other), do: {:error, {:unexpected_response, other}}
end
