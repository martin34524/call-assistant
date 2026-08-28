defmodule CallAssistant.Claude do
  @moduledoc """
  Behaviour for classifying a finished call and (when warranted) drafting
  a follow-up: does it need an admin's attention, and if so, is there
  enough in the transcript for the app to place the follow-up call on its
  own? See `CallAssistant.Leads.Escalation`, which is the only caller.

  There is no structured signal for any of this anywhere in CALL-E's
  API (confirmed via `calle mcp tools`: only plan_call/run_call/
  get_call_run exist) - it requires actual language understanding of the
  transcript, which is why this exists as a separate LLM integration
  rather than something derived from CALL-E's own response.

  Two implementations, mirroring `CallAssistant.CallE`'s Mock/Live shape:

    * `CallAssistant.Claude.Mock` - deterministic, no network. Default in
      tests (config/test.exs).
    * `CallAssistant.Claude.Live` - the real thing: raw HTTP to the
      Claude API via `Req` (Elixir has no official Anthropic SDK).
      Returns `{:error, :not_configured}` if `ANTHROPIC_API_KEY` isn't
      set - same fail-open shape as `CallAssistant.CallE.Live`'s missing
      base URL, so a missing key never crashes anything, it just means
      no lead ever gets escalated.

  Select the implementation via `config :call_assistant, :claude_client`.
  """

  alias CallAssistant.Leads.Lead

  @type classification :: %{
          needs_escalation: boolean(),
          reason: String.t() | nil,
          auto_handleable: boolean(),
          suggested_goal: String.t() | nil
        }

  @callback classify_call(Lead.t()) :: {:ok, classification()} | {:error, term()}

  def client do
    Application.get_env(:call_assistant, :claude_client, CallAssistant.Claude.Mock)
  end
end
