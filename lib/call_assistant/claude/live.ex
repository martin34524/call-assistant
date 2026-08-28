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

  See `CallAssistant.Claude.Gemini` for the same job via Google's API,
  for when a Gemini key is available instead of an Anthropic one.
  """

  @behaviour CallAssistant.Claude

  require Logger

  alias CallAssistant.Claude.Prompt

  @endpoint "https://api.anthropic.com/v1/messages"
  @model "claude-opus-5"

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
      system: Prompt.system_prompt(),
      messages: [%{role: "user", content: Prompt.user_message(lead)}]
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

  defp parse_response(%{"content" => content}) do
    with %{"text" => text} <- Enum.find(content, &(&1["type"] == "text")),
         {:ok, decoded} <- Jason.decode(String.trim(text)),
         {:ok, classification} <- Prompt.validate(decoded) do
      {:ok, classification}
    else
      nil -> {:error, {:unexpected_response, "no text block in response"}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_response(other), do: {:error, {:unexpected_response, other}}
end
