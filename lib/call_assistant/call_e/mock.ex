defmodule CallAssistant.CallE.Mock do
  @moduledoc """
  Simulates CALL-E's plan_call / run_call / get_call_run contract with
  realistic timing and varied outcomes, so the lead-qualification flow can
  be built and demoed without real CALL-E access.

  State for in-flight "calls" is kept in an Agent-backed map, keyed by
  call_run_id, and advances a step each time get_call_run polls it.
  """

  @behaviour CallAssistant.CallE

  use Agent

  @outcomes [:completed_success, :completed_partial, :no_answer, :declined, :failed]

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @impl true
  def plan_call(%{to_phone: phone, goal: goal}) do
    plan_id = "plan_" <> rand_id()
    confirm_token = "confirm_" <> rand_id()

    :ok = ensure_started()

    Agent.update(__MODULE__, fn state ->
      Map.put(state, plan_id, %{phone: phone, goal: goal, confirm_token: confirm_token})
    end)

    {:ok,
     %{
       plan_id: plan_id,
       ready_to_run: true,
       confirm_token: confirm_token,
       clarifying_questions: []
     }}
  end

  @impl true
  def run_call(%{plan_id: plan_id, confirm_token: confirm_token}) do
    :ok = ensure_started()

    case Agent.get(__MODULE__, &Map.get(&1, plan_id)) do
      %{confirm_token: ^confirm_token} = plan ->
        call_run_id = "run_" <> rand_id()
        outcome = Enum.random(@outcomes)
        # Mock "answers" after a couple of polls so the dashboard visibly
        # transitions through in_progress before settling.
        polls_until_done = Enum.random(2..4)

        Agent.update(__MODULE__, fn state ->
          state
          |> Map.put(call_run_id, %{
            plan: plan,
            outcome: outcome,
            polls_seen: 0,
            polls_until_done: polls_until_done
          })
          |> Map.delete(plan_id)
        end)

        {:ok, %{call_run_id: call_run_id, status: "in_progress"}}

      _ ->
        {:error, :unknown_or_expired_plan}
    end
  end

  @impl true
  def get_call_run(%{call_run_id: call_run_id}) do
    :ok = ensure_started()

    case Agent.get_and_update(__MODULE__, fn state ->
           case Map.get(state, call_run_id) do
             nil ->
               {nil, state}

             call ->
               updated = %{call | polls_seen: call.polls_seen + 1}
               {updated, Map.put(state, call_run_id, updated)}
           end
         end) do
      nil ->
        {:error, :unknown_call_run}

      %{polls_seen: seen, polls_until_done: until_done} when seen < until_done ->
        {:ok,
         %{
           status: "in_progress",
           message: in_progress_message(seen),
           transcript: nil,
           summary: nil,
           task_completed: nil
         }}

      call ->
        {:ok, terminal_result(call)}
    end
  end

  defp terminal_result(%{outcome: :no_answer, plan: _plan}) do
    %{
      status: "no_answer",
      message: "No answer after ringing.",
      transcript: nil,
      summary: "Nobody answered the call.",
      task_completed: false
    }
  end

  defp terminal_result(%{outcome: :declined, plan: plan}) do
    %{
      status: "declined",
      message: "Call ended from realtime events.",
      transcript: mock_transcript(plan, "Actually, I'm not interested, please don't call again."),
      summary: "The recipient declined to continue and asked not to be called again.",
      task_completed: false
    }
  end

  defp terminal_result(%{outcome: :failed, plan: plan}) do
    %{
      status: "failed",
      message: "Call could not be connected.",
      transcript: nil,
      summary: "Call could not be connected to #{plan.phone}.",
      task_completed: false
    }
  end

  defp terminal_result(%{outcome: :completed_success, plan: plan}) do
    reply =
      "Yeah, we're still interested - budget is around $10,000-$25,000 and we'd like to move " <>
        "forward within the next 2 weeks. I'm the decision maker, and yes please have someone call me back."

    %{
      status: "completed",
      message: "Call ended from realtime events.",
      transcript: mock_transcript(plan, reply),
      summary:
        "The lead confirmed continued interest with a budget of roughly $10,000-$25,000 and a " <>
          "2-week timeline. They are the decision maker and requested a callback from a sales rep.",
      task_completed: true
    }
  end

  defp terminal_result(%{outcome: :completed_partial, plan: plan}) do
    reply = "We might be interested but I'm not sure yet, can you call back another time?"

    %{
      status: "completed",
      message: "Call ended from realtime events.",
      transcript: mock_transcript(plan, reply),
      summary:
        "The lead was noncommittal - open to a future conversation but didn't give budget or " <>
          "timeline details and asked to be called back later.",
      task_completed: true
    }
  end

  # Mirrors the real CALL-E status message text observed while a call is
  # ringing/connecting, so the dashboard's live status line looks the same
  # in dev as it does against a real call.
  defp in_progress_message(0), do: "run_call started."
  defp in_progress_message(1), do: "botlab create bot."
  defp in_progress_message(_), do: "calling task status=calling"

  # Timestamped [HH:MM:SS] BOT:/USER: lines, matching the real transcript
  # format returned by CALL-E, so the call-logs viewer parses both alike.
  defp mock_transcript(plan, reply) do
    turns = [
      {"BOT", "Hi, this is calling about your recent inquiry. Do you have a minute?"},
      {"USER", "Sure, go ahead."},
      {"BOT", plan.goal},
      {"USER", reply},
      {"BOT", "Thank you, I'll pass that along. Have a great day!"}
    ]

    turns
    |> Enum.with_index(fn {speaker, text}, i ->
      seconds = i * 5
      "[#{format_timestamp(seconds)}] #{speaker}: #{text}"
    end)
    |> Enum.join("\n")
  end

  defp format_timestamp(total_seconds) do
    minutes = div(total_seconds, 60)
    seconds = rem(total_seconds, 60)
    :io_lib.format("00:~2..0B:~2..0B", [minutes, seconds]) |> to_string()
  end

  defp ensure_started do
    case Process.whereis(__MODULE__) do
      nil ->
        case start_link([]) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end

      _pid ->
        :ok
    end
  end

  defp rand_id, do: :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
end
