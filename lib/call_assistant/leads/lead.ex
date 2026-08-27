defmodule CallAssistant.Leads.Lead do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(new planning needs_clarification ready_to_run in_progress qualified disqualified no_answer failed)

  schema "leads" do
    field :name, :string
    field :phone, :string
    field :source, :string, default: "manual"
    field :status, :string, default: "new"

    field :goal, :string

    field :plan_id, :string
    field :confirm_token, :string
    field :call_run_id, :string

    field :interested, :boolean
    field :budget, :string
    field :timeline, :string
    field :decision_maker, :boolean
    field :callback_requested, :boolean
    field :notes, :string
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
      :interested,
      :budget,
      :timeline,
      :decision_maker,
      :callback_requested,
      :notes,
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
