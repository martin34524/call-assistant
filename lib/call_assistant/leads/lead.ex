defmodule CallAssistant.Leads.Lead do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(new planning needs_clarification ready_to_run in_progress completed no_answer declined failed)

  schema "leads" do
    field :name, :string
    field :phone, :string
    field :source, :string, default: "manual"
    field :status, :string, default: "new"

    field :goal, :string

    field :plan_id, :string
    field :confirm_token, :string
    field :call_run_id, :string

    # What CALL-E's get_call_run actually returns for a finished call:
    # whether the agent judged the goal accomplished, its natural-language
    # summary of what happened/was learned, and the full transcript. There
    # is no separate structured-data extraction API - if you want specific
    # fields (budget, timeline, ...), the goal has to ask for them and a
    # human (or a downstream parse of `summary`) reads the answer back out.
    field :task_completed, :boolean
    field :summary, :string
    field :transcript, :string
    field :error, :string

    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses

  @doc false
  def create_changeset(lead, attrs) do
    lead
    |> cast(attrs, [:name, :phone, :source, :goal])
    |> validate_required([:name, :phone])
    |> validate_format(:phone, ~r/^\+?[0-9\s\-\(\)]{7,20}$/,
      message: "must be a valid phone number"
    )
    |> put_default_goal()
  end

  @doc false
  def update_changeset(lead, attrs) do
    lead
    |> cast(attrs, [
      :status,
      :plan_id,
      :confirm_token,
      :call_run_id,
      :task_completed,
      :summary,
      :transcript,
      :error
    ])
    |> validate_inclusion(:status, @statuses)
  end

  defp put_default_goal(changeset) do
    case get_field(changeset, :goal) do
      nil ->
        name = get_field(changeset, :name)

        put_change(
          changeset,
          :goal,
          "Call #{name} to qualify them as a sales lead. Politely confirm you're reaching out " <>
            "about their recent inquiry, then find out: (1) their approximate budget, " <>
            "(2) their timeline to move forward, (3) whether they are the decision maker, " <>
            "and (4) whether they'd like a callback from a sales rep. Be brief and friendly."
        )

      _ ->
        changeset
    end
  end
end
