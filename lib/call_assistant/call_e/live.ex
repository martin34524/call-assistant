defmodule CallAssistant.CallE.Live do
  @moduledoc """
  Speculative CALL-E HTTP adapter for a static-API-key REST surface.

  PREFER `CallAssistant.CallE.Cli` INSTEAD. A real call verified that
  CALL-E's actual, working integration path is the `calle` CLI's brokered
  OAuth login talking to its MCP endpoint - the public repo does not
  document a static-API-key REST API at all. This module is speculative:
  it assumes a conventional REST shape (POST /v1/calls/plan, .../run,
  GET /v1/calls/:id) with Bearer-token auth, in case CALL-E exposes such
  an API for server deployments where running `calle auth login`
  interactively isn't practical. None of this has been verified against
  a real endpoint.

  Response field names below (task_completed, summary) match what the
  real MCP tool returns (see CallAssistant.CallE moduledoc) as a
  best guess for what an equivalent REST API would return - but again,
  unverified.

  Before trusting this in production, confirm against real CALL-E
  developer docs / support:
    * whether this REST surface exists at all
    * the actual base URL (placeholder below)
    * exact request/response field names for plan/run/status

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
           ready_to_run: Map.get(data, "ready_to_run", false),
           confirm_token: Map.get(data, "confirm_token"),
           clarifying_questions: Map.get(data, "clarifying_questions", [])
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
           summary: Map.get(data, "summary"),
           task_completed: Map.get(data, "task_completed")
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
