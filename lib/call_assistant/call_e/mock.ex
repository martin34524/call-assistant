defmodule CallAssistant.CallE.Mock do
  @moduledoc """
  Simulates CALL-E's plan_call / run_call / get_call_run contract with
  realistic timing and varied outcomes, so the lead-qualification flow can
  be built and demoed without real CALL-E credentials.

  State for in-flight "calls" is kept in an Agent-backed ETS-free map,
  keyed by call_run_id, and advances a step each time get_call_run polls it.
  """

  @behaviour CallAssistant.CallE

  use Agent

  @outcomes [:qualified_hot, :qualified_cold, :not_interested, :no_answer, :failed]

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

    {:ok, %{plan_id: plan_id, ready_to_run: true, confirm_token: confirm_token}}
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
        {:ok, %{status: "in_progress", transcript: nil, structured_result: nil}}

      call ->
        {:ok, terminal_result(call)}
    end
  end

  defp terminal_result(%{outcome: :no_answer, plan: plan}) do
    %{
      status: "no_answer",
      transcript: "[no answer after 6 rings - #{plan.phone}]",
      structured_result: nil
    }
  end

  defp terminal_result(%{outcome: :failed, plan: plan}) do
    %{
      status: "failed",
      transcript: nil,
      structured_result: %{"error" => "call could not be connected to #{plan.phone}"}
    }
  end

  defp terminal_result(%{outcome: outcome, plan: plan}) do
    {interested, budget, timeline, notes} = qualification_for(outcome)

    %{
      status: "completed",
      transcript: mock_transcript(plan, interested, budget, timeline),
      structured_result: %{
        "interested" => interested,
        "budget" => budget,
        "timeline" => timeline,
        "decision_maker" => Enum.random([true, true, false]),
        "callback_requested" => interested,
        "notes" => notes
      }
    }
  end

  defp qualification_for(:qualified_hot) do
    {true, Enum.random(["$5,000-$10,000", "$10,000-$25,000", "$25,000+"]),
     Enum.random(["this week", "within 2 weeks", "this month"]),
     "Very engaged, asked follow-up questions, wants a callback ASAP."}
  end

  defp qualification_for(:qualified_cold) do
    {true, Enum.random(["under $5,000", "$5,000-$10,000"]),
     Enum.random(["next quarter", "no firm timeline"]),
     "Interested but not urgent, open to a follow-up call later."}
  end

  defp qualification_for(:not_interested) do
    {false, nil, nil, "Said they are no longer looking / went with a competitor."}
  end

  defp mock_transcript(plan, interested, budget, timeline) do
    lines = [
      "Agent: Hi, this is CALL-E calling about your recent inquiry. Do you have a minute?",
      "Lead: Sure, go ahead.",
      "Agent: #{plan.goal}"
    ]

    lines =
      if interested do
        lines ++
          [
            "Lead: Yeah we're still interested, budget is around #{budget}.",
            "Agent: Great, and what's your timeline?",
            "Lead: #{timeline}.",
            "Agent: Perfect, I'll have someone follow up. Thanks for your time!"
          ]
      else
        lines ++
          [
            "Lead: Actually we're not moving forward with this.",
            "Agent: Understood, thanks for letting us know."
          ]
      end

    Enum.join(lines, "\n")
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
