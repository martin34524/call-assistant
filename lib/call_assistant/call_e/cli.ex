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

  Field names for `plan_call`'s response (`plan_id`, `ready_to_run`,
  `confirm_token`, `clarifying_questions`) were verified against a real
  `calle call plan --json` response. Field names for `run_call` and
  `get_call_run` are inferred from the MCP docs (docs/mcp/openagent-oauth.md
  in the integrations repo) and CALL-E.Live's existing assumptions, but
  have NOT been verified against a real response, since doing so requires
  actually placing a phone call. If a real call's output doesn't match,
  adjust `run_call/1` and `get_call_run/1` below against the real JSON -
  everything is parsed defensively so a shape mismatch surfaces as a
  clear `{:error, {:unexpected_response, _}}` rather than a crash.
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
        %{"call_run_id" => call_run_id} = data ->
          {:ok, %{call_run_id: call_run_id, status: Map.get(data, "status", "in_progress")}}

        %{"run_id" => run_id} = data ->
          {:ok, %{call_run_id: run_id, status: Map.get(data, "status", "in_progress")}}

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
        %{"status" => status} = data ->
          {:ok,
           %{
             status: status,
             transcript: Map.get(data, "transcript"),
             structured_result: Map.get(data, "structured_result") || Map.get(data, "result")
           }}

        other ->
          {:error, {:unexpected_response, other}}
      end
    end
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
