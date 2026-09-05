defmodule CallAssistant.CallE.Cli do
  @moduledoc """
  Adapter that shells out to the official `calle` CLI
  (https://github.com/CALLE-AI/call-e-integrations) instead of talking to
  CALL-E's HTTP API directly.

  This is the real, working integration path: the CLI handles the
  brokered OAuth login and caches a bearer token locally (see
  `calle auth login` / `calle auth status`), then talks to the real MCP
  endpoint on our behalf via `calle call plan|run|status --json`. There is
  no separate API key to manage - whoever runs this app just needs to
  have run `calle auth login` once on the host machine.

  Every field name below (`plan_id`, `ready_to_run`, `confirm_token`,
  `clarifying_questions`, `run_id`, `status`, and the `result.summary` /
  `result.post_summary` / `result.outcome.task_completed` /
  `result.transcript` nesting under get_call_run) was verified against a
  real call placed through `calle call plan|run|status --json`. CALL-E's
  own `status` values are uppercase with spaces (e.g. "NO ANSWER"); this
  adapter downcases and underscores them to match the rest of the app
  (`no_answer`, `completed`, `declined`, `failed`, plus in-flight values
  like `preparing`/`scheduled` that the Qualifier just keeps polling on).
  Everything is still parsed defensively so an unexpected shape surfaces
  as a clear `{:error, {:unexpected_response, _}}` rather than a crash.
  """

  @behaviour CallAssistant.CallE

  require Logger

  @impl true
  def plan_call(%{to_phone: phone, goal: goal} = params) do
    args =
      ["call", "plan", "--to-phone", phone, "--goal", goal, "--json"] ++
        optional_arg("--language", Map.get(params, :language)) ++
        optional_arg("--region", Map.get(params, :region))

    with {:ok, sc} <- run_tool(args) do
      case sc do
        %{"plan_id" => plan_id} ->
          {:ok,
           %{
             plan_id: plan_id,
             ready_to_run: Map.get(sc, "ready_to_run", false),
             confirm_token: Map.get(sc, "confirm_token"),
             clarifying_questions: Map.get(sc, "clarifying_questions", [])
           }}

        other ->
          {:error, {:unexpected_response, other}}
      end
    end
  end

  @impl true
  def run_call(%{plan_id: plan_id, confirm_token: confirm_token}) do
    args = ["call", "run", "--plan-id", plan_id, "--confirm-token", confirm_token, "--json"]

    with {:ok, sc} <- run_tool(args) do
      case sc do
        %{"run_id" => run_id} = data ->
          {:ok, %{call_run_id: run_id, status: normalize_status(Map.get(data, "status"))}}

        other ->
          {:error, {:unexpected_response, other}}
      end
    end
  end

  @impl true
  def get_call_run(%{call_run_id: call_run_id}) do
    args = ["call", "status", "--run-id", call_run_id, "--json"]

    with {:ok, sc} <- run_tool(args) do
      case sc do
        %{"status" => raw_status} = data ->
          result = Map.get(data, "result") || %{}

          {:ok,
           %{
             status: normalize_status(raw_status),
             message: Map.get(data, "message"),
             transcript: Map.get(result, "transcript"),
             summary: Map.get(result, "post_summary") || Map.get(result, "summary"),
             task_completed: get_in(result, ["outcome", "task_completed"])
           }}

        other ->
          {:error, {:unexpected_response, other}}
      end
    end
  end

  # CALL-E's status strings are uppercase, sometimes with spaces
  # (PREPARING, SCHEDULED, COMPLETED, "NO ANSWER", DECLINED, FAILED).
  # Normalize to the lowercase/underscored vocabulary used throughout
  # the rest of this app.
  defp normalize_status(nil), do: "unknown"

  defp normalize_status(status) do
    status |> String.downcase() |> String.replace(" ", "_")
  end

  defp optional_arg(_flag, nil), do: []
  defp optional_arg(_flag, ""), do: []
  defp optional_arg(flag, value), do: [flag, value]

  defp run_tool(args) do
    case System.cmd("calle", args, stderr_to_stdout: true) do
      {output, 0} ->
        parse_tool_response(output)

      {output, exit_code} ->
        Logger.warning("calle CLI exited #{exit_code}: #{output}")
        {:error, parse_cli_failure(output, exit_code)}
    end
  rescue
    e in ErlangError ->
      {:error, {:cli_not_found, Exception.message(e)}}
  end

  defp parse_tool_response(output) do
    with {:ok, %{"ok" => true, "result" => result}} <- decode_cli_json(output),
         %{"isError" => false, "structuredContent" => sc} <- result do
      {:ok, sc}
    else
      {:ok, %{"ok" => false} = data} ->
        {:error, call_failure(data)}

      %{"isError" => true} = result ->
        {:error, {:tool_error, result}}

      {:error, %Jason.DecodeError{}} ->
        {:error, {:invalid_json, output}}

      other ->
        {:error, {:unexpected_response, other}}
    end
  end

  # A non-zero exit's stdout is the *same* {"ok": false, ...} JSON body a
  # zero-exit "soft" failure carries (see parse_tool_response/1) - the
  # CLI just also happened to exit non-zero this time. Parse it the same
  # way instead of discarding it, falling back to the opaque exit tuple
  # only when the output genuinely isn't that shape (the binary crashed
  # outright, wrote garbage, etc). Public (not `defp`) only so this parsing
  # itself - the actual logic this module exists to get right - is
  # directly unit-testable without shelling out to a real `calle` binary;
  # not part of the CallE behaviour contract, so @doc false.
  @doc false
  def parse_cli_failure(output, exit_code) do
    case decode_cli_json(output) do
      {:ok, %{"ok" => false} = data} -> call_failure(data)
      _ -> {:cli_exit, exit_code, output}
    end
  end

  # On any "ok": false response (confirmed on real plan_call/run_call
  # failures, exit code 0 or not), the calle CLI's stdout is its --json
  # body immediately followed by a plain-text duplicate of the same
  # error message on its own trailing line - e.g.:
  #
  #     {
  #       "ok": false,
  #       ...
  #     }
  #     plan_call failed: fetch failed
  #
  # That trailing line is bytes after the JSON value's closing brace, so
  # Jason.decode/1 on the raw output fails outright ("unexpected trailing
  # data"). The CLI always pretty-prints with the top-level object's own
  # braces unindented and every nested one indented - a raw newline can
  # only be pretty-print whitespace, never string content, since a real
  # newline byte inside a JSON string would make the JSON itself invalid
  # - so cutting the input at the first bare "\n}" reliably isolates just
  # the JSON value regardless of what (if anything) follows it.
  defp decode_cli_json(output) do
    case Regex.run(~r/\A(\{.*?\n\})/s, output) do
      [_, json] -> Jason.decode(json)
      nil -> Jason.decode(output)
    end
  end

  # Turns the CLI's own failure JSON into what the rest of the app
  # actually needs: a clean, human-readable message, and whether CALL-E's
  # server may have already accepted/started the call before this
  # attempt failed (call_started true *or* "unknown" - both mean "don't
  # assume nothing happened"; only a plain false means the CLI confirmed
  # no call was ever placed). recovery_id (present when call_started
  # isn't false) lets a human check the real outcome via `calle call
  # recover` directly - this app doesn't attempt automatic recovery.
  defp call_failure(data) do
    {:call_failure,
     %{
       message: get_in(data, ["error", "message"]) || "call failed",
       call_uncertain: Map.get(data, "call_started") in [true, "unknown"],
       recovery_id: Map.get(data, "recovery_id")
     }}
  end
end
