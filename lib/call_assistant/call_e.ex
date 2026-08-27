defmodule CallAssistant.CallE do
  @moduledoc """
  Behaviour for the CALL-E phone-agent integration, matching the
  plan_call / run_call / get_call_run contract used by CALL-E's MCP tools
  (see https://github.com/CALLE-AI/call-e-integrations, docs/mcp/openagent-oauth.md).

  Two implementations are provided:

    * `CallAssistant.CallE.Mock` - simulates realistic call outcomes, no
      network calls. Used by default so the app is fully testable without
      real CALL-E credentials.
    * `CallAssistant.CallE.Live` - talks to a real CALL-E HTTP endpoint.
      The public repo only documents an OAuth browser-login flow for the
      MCP endpoint; it does not document a static-API-key REST surface.
      This adapter assumes a conventional REST shape (POST /v1/calls,
      GET /v1/calls/:id) with Bearer-token auth. Confirm the real base URL
      and payload shape against CALL-E's developer API docs / support
      before relying on it - see lib/call_assistant/call_e/live.ex.

  Select the implementation via `config :call_assistant, :call_e_client`.
  """

  @type plan_params :: %{
          required(:to_phone) => String.t(),
          optional(:region) => String.t(),
          optional(:language) => String.t(),
          required(:goal) => String.t(),
          optional(:user_input) => map()
        }

  @callback plan_call(plan_params()) ::
              {:ok,
               %{
                 plan_id: String.t(),
                 ready_to_run: boolean(),
                 confirm_token: String.t() | nil,
                 clarifying_questions: [String.t()]
               }}
              | {:error, term()}

  @callback run_call(%{plan_id: String.t(), confirm_token: String.t()}) ::
              {:ok, %{call_run_id: String.t(), status: String.t()}} | {:error, term()}

  @callback get_call_run(%{call_run_id: String.t()}) ::
              {:ok,
               %{
                 status: String.t(),
                 transcript: String.t() | nil,
                 structured_result: map() | nil
               }}
              | {:error, term()}

  @terminal_statuses ~w(completed failed no_answer)

  def terminal_statuses, do: @terminal_statuses

  def client do
    Application.get_env(:call_assistant, :call_e_client, CallAssistant.CallE.Mock)
  end
end
