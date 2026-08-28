defmodule CallAssistant.Claude.Gemini do
  @moduledoc """
  Real classifier, same job as `CallAssistant.Claude.Live` but via
  Google's Gemini API instead of Anthropic's - for when a `GEMINI_API_KEY`
  is available instead of an `ANTHROPIC_API_KEY`. Same prompt and JSON
  contract (`CallAssistant.Claude.Prompt`), just a different transport.

  Configure via:

      config :call_assistant, :gemini_api_key,
        System.get_env("GEMINI_API_KEY")
  """

  @behaviour CallAssistant.Claude

  require Logger

  alias CallAssistant.Claude.Prompt

  @model "gemini-3.6-flash"
  @endpoint "https://generativelanguage.googleapis.com/v1beta/models/#{@model}:generateContent"

  @impl true
  def classify_call(lead) do
    api_key = Application.get_env(:call_assistant, :gemini_api_key)

    if is_nil(api_key) or api_key == "" do
      {:error, :not_configured}
    else
      request(api_key, lead)
    end
  end

  defp request(api_key, lead) do
    body = %{
      system_instruction: %{parts: [%{text: Prompt.system_prompt()}]},
      contents: [%{role: "user", parts: [%{text: Prompt.user_message(lead)}]}],
      generationConfig: %{responseMimeType: "application/json"}
    }

    case Req.post(@endpoint,
           headers: [{"x-goog-api-key", api_key}],
           json: body,
           receive_timeout: 30_000
         ) do
      {:ok, %Req.Response{status: 200, body: resp_body}} ->
        parse_response(resp_body)

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        Logger.warning("Gemini API error #{status}: #{inspect(resp_body)}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.warning("Gemini API request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_response(%{"candidates" => [%{"content" => %{"parts" => parts}} | _]}) do
    with %{"text" => text} <- Enum.find(parts, &Map.has_key?(&1, "text")),
         {:ok, decoded} <- Jason.decode(String.trim(text)),
         {:ok, classification} <- Prompt.validate(decoded) do
      {:ok, classification}
    else
      nil -> {:error, {:unexpected_response, "no text part in response"}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_response(other), do: {:error, {:unexpected_response, other}}
end
