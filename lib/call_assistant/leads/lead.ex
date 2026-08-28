defmodule CallAssistant.Leads.Lead do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(new planning needs_clarification ready_to_run in_progress completed no_answer declined failed)

  schema "leads" do
    field :name, :string
    field :phone, :string
    field :source, :string, default: "manual"
    field :department, :string
    field :status, :string, default: "new"

    # Free-text instructions from whoever set up the call: what this call
    # is actually about (first-touch intro, relaying specific information,
    # a qualification script, ...). Combined with the opening line to
    # build `goal`, the literal instruction sent to CALL-E.
    field :context, :string
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
    |> cast(attrs, [:name, :phone, :source, :department, :context, :goal])
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

  @default_purpose "Let them know you're reaching out to introduce yourself and see how you " <>
                     "can help. Ask if now is a good time to talk."

  defp put_default_goal(changeset) do
    case get_field(changeset, :goal) do
      nil ->
        name = get_field(changeset, :name)
        opening = opening_line(get_field(changeset, :department))
        purpose = blank_to_nil(get_field(changeset, :context)) || @default_purpose

        put_change(
          changeset,
          :goal,
          "Start the call with this exact introduction: \"#{opening}\" Then, speaking with " <>
            "#{name}: #{purpose} Keep the tone brief and friendly. At the end, report back a " <>
            "summary of what was discussed and anything #{name} asked for or wants as a follow-up."
        )

      _ ->
        changeset
    end
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  @doc """
  The caller identity opened with at the start of every call: the
  organization name (config :call_assistant, :organization_name, default
  "MacDevs"), plus the lead's department when one is set, e.g. "Hi, this
  is MacDevs CEO's Office calling" vs. "Hi, this is MacDevs calling" for
  leads with no department (routes to no particular office/role).
  """
  def opening_line(department) do
    org = Application.get_env(:call_assistant, :organization_name, "MacDevs")

    who =
      case blank_to_nil(department) do
        nil -> org
        dept -> "#{org} #{dept}"
      end

    "Hi, this is #{who} calling."
  end
end
