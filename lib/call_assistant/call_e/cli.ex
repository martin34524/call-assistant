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
        {:error, {:cli_exit, exit_code, output}}
    end
  rescue
    e in ErlangError ->
      {:error, {:cli_not_found, Exception.message(e)}}
  end

  defp parse_tool_response(output) do
    with {:ok, %{"ok" => true, "result" => result}} <- Jason.decode(output),
         %{"isError" => false, "structuredContent" => sc} <- result do
      {:ok, sc}
    else
      {:ok, %{"ok" => false} = data} ->
        {:error, {:cli_error, data}}

      %{"isError" => true} = result ->
        {:error, {:tool_error, result}}

      {:error, %Jason.DecodeError{}} ->
        {:error, {:invalid_json, output}}

      other ->
        {:error, {:unexpected_response, other}}
    end
  end
end
