defmodule CallAssistant.CallE do
  @moduledoc """
  Behaviour for the CALL-E phone-agent integration, matching the
  plan_call / run_call / get_call_run contract used by CALL-E's MCP tools
  (see https://github.com/CALLE-AI/call-e-integrations, docs/mcp/openagent-oauth.md).

  Verified against a real call placed through the `calle` CLI: CALL-E does
  NOT return custom structured fields (no "budget", "interested", etc.) -
  a finished call run's result is `status` (one of, per CALL-E's own tool
  schema: PREPARING, SCHEDULED, COMPLETED, "NO ANSWER", DECLINED, FAILED),
  a natural-language `summary`, `outcome.task_completed` (whether the
  agent judged the goal accomplished), and the full `transcript`. If an
  app wants specific data points out of a call, the goal has to ask for
  them and a human (or a downstream parse of `summary`) reads the answer
  back out - CALL-E doesn't extract them into typed fields itself.

  Three implementations are provided:

    * `CallAssistant.CallE.Mock` - simulates realistic call outcomes, no
      network calls or CLI required. Used by default so the app is fully
      testable without real CALL-E access.
    * `CallAssistant.CallE.Cli` - the real, working integration: shells
      out to the official `calle` CLI, which handles brokered OAuth login
      and talks to CALL-E's actual MCP endpoint. Requires `calle auth
      login` to have been run once on the host (see `calle auth status`).
    * `CallAssistant.CallE.Live` - talks to a raw CALL-E HTTP endpoint
      directly. The public repo only documents OAuth browser login for
      the MCP endpoint, not a static-API-key REST surface, so this
      adapter's endpoint shape is an unverified best guess - prefer `Cli`.

  Select the implementation via `config :call_assistant, :call_e_client`.
  """

  @type plan_params :: %{
          required(:to_phone) => String.t(),
          optional(:region) => String.t(),
          optional(:language) => String.t(),
          required(:goal) => String.t(),
          # Both set together to resume a plan that came back
          # ready_to_run: false (see CallAssistant.Leads.Qualifier.resume/2):
          # plan_id from that earlier response, user_input as the human's
          # free-text answer to its clarifying_questions. Absent on a
          # fresh, first-time plan_call.
          optional(:plan_id) => String.t(),
          optional(:user_input) => String.t()
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
                 # CALL-E's own human-readable status line (e.g. "calling
                 # task status=calling", "Call ended from realtime
                 # events."). This is the only live signal available while
                 # a call is in progress - there is no distinct "answered"/
                 # "person is now talking" boolean in the API, and the
                 # transcript itself is only populated once the call
                 # reaches a terminal status, not streamed live.
                 message: String.t() | nil,
                 transcript: String.t() | nil,
                 summary: String.t() | nil,
                 task_completed: boolean() | nil
               }}
              | {:error, term()}

  @terminal_statuses ~w(completed failed no_answer declined)

  def terminal_statuses, do: @terminal_statuses

  def client do
    Application.get_env(:call_assistant, :call_e_client, CallAssistant.CallE.Mock)
  end
end
