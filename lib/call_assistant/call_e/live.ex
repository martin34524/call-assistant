defmodule CallAssistant.CallE.Live do
  @moduledoc """
  Real CALL-E HTTP adapter.

  IMPORTANT: the public call-e-integrations repo only documents an OAuth
  browser-login flow for the MCP endpoint (docs/mcp/openagent-oauth.md) -
  it does not publish a static-API-key REST spec. This adapter is written
  against the conventional REST shape implied by the project README
  ("Developer API: Direct HTTP endpoints ... call creation, status
  retrieval, event tracking"), using Bearer-token auth with the API key
  you provided.

  Before trusting this in production, confirm against real CALL-E
  developer docs / support:
    * the actual base URL (placeholder below)
    * exact request/response field names for plan/run/status
    * whether "plan then run" is a single call-creation step in the REST
      API (unlike the two-step MCP tool contract) or two-step there too

  Configure via:

      config :call_assistant, :call_e,
        base_url: System.get_env("CALLE_API_BASE_URL"),
        api_key: System.get_env("CALLE_API_KEY")
  """

  @behaviour CallAssistant.CallE

  @impl true
  def plan_call(%{to_phone: phone, goal: goal} = params) do
    body = %{
      to_phone: phone,
      region: Map.get(params, :region),
      language: Map.get(params, :language, "en"),
      goal: goal,
      user_input: Map.get(params, :user_input, %{})
    }

    case request(:post, "/v1/calls/plan", body) do
      {:ok, %{"plan_id" => plan_id} = data} ->
        {:ok,
         %{
           plan_id: plan_id,
           ready_to_run: Map.get(data, "ready_to_run", true),
           confirm_token: Map.get(data, "confirm_token")
         }}

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      error ->
        error
    end
  end

  @impl true
  def run_call(%{plan_id: plan_id, confirm_token: confirm_token}) do
    body = %{plan_id: plan_id, confirm_token: confirm_token}

    case request(:post, "/v1/calls/run", body) do
      {:ok, %{"call_run_id" => call_run_id} = data} ->
        {:ok, %{call_run_id: call_run_id, status: Map.get(data, "status", "in_progress")}}

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      error ->
        error
    end
  end

  @impl true
  def get_call_run(%{call_run_id: call_run_id}) do
    case request(:get, "/v1/calls/#{call_run_id}", nil) do
      {:ok, data} ->
        {:ok,
         %{
           status: Map.fetch!(data, "status"),
           transcript: Map.get(data, "transcript"),
           structured_result: Map.get(data, "structured_result")
         }}

      error ->
        error
    end
  end

  defp request(method, path, body) do
    config = Application.get_env(:call_assistant, :call_e, [])
    base_url = Keyword.get(config, :base_url)
    api_key = Keyword.get(config, :api_key)

    cond do
      is_nil(base_url) or base_url == "" ->
        {:error, :calle_base_url_not_configured}

      is_nil(api_key) or api_key == "" ->
        {:error, :calle_api_key_not_configured}

      true ->
        opts = [
          method: method,
          url: base_url <> path,
          headers: [{"authorization", "Bearer #{api_key}"}],
          json: body,
          receive_timeout: 30_000
        ]

        opts = if is_nil(body), do: Keyword.delete(opts, :json), else: opts

        case Req.request(opts) do
          {:ok, %Req.Response{status: status, body: resp_body}} when status in 200..299 ->
            {:ok, resp_body}

          {:ok, %Req.Response{status: status, body: resp_body}} ->
            {:error, {:http_error, status, resp_body}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end
end
