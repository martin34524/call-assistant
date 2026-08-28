defmodule CallAssistant.Leads.Lead do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(new planning needs_clarification ready_to_run in_progress completed no_answer declined failed cancelled)
  @escalation_statuses ~w(pending auto_handled resolved)

  schema "leads" do
    field :name, :string
    field :phone, :string
    field :source, :string, default: "manual"
    belongs_to :department, CallAssistant.Departments.Department
    # Set by CallAssistant.Leads.create_lead/2 from the resolved
    # department before building the changeset - not persisted, only
    # used to word the opening line (see opening_line/1 and
    # put_default_goal/1 below), since the changeset only otherwise has
    # department_id (an integer) to work with.
    field :department_name, :string, virtual: true
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

    # CALL-E's own human-readable status line, updated on every poll while
    # the call is in progress (e.g. "botlab create bot.", "calling task
    # status=calling"). The only live signal available - there's no
    # distinct "answered"/"person is now talking" boolean.
    field :status_message, :string

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

    # Post-call handoff (see CallAssistant.Leads.Escalation): CALL-E has
    # no live call-transfer capability, so this only ever runs after a
    # call completes. nil = never escalated; "pending" = needs an admin's
    # review (counts toward the sidebar badge); "auto_handled" = the
    # system placed a follow-up call itself (see follow_up_of_id below,
    # on that new lead) without waiting for a human; "resolved" = an
    # admin reviewed/dismissed a "pending" one.
    field :escalation_status, :string
    field :escalation_reason, :string
    field :suggested_follow_up_goal, :string
    # Which department the classifier thinks the follow-up actually
    # belongs to (e.g. an Admin-line call that turns out to be a Finance
    # request) - nil means "no reroute, follow up from wherever this call
    # already happened" (CallAssistant.Leads.Escalation resolves that to
    # the admin department). Never trusted as an id straight from the
    # classifier - always resolved against a real %Department{} first.
    belongs_to :suggested_department, CallAssistant.Departments.Department
    # Set on a follow-up call's own lead record, pointing back at the
    # original call it followed up on.
    belongs_to :follow_up_of, __MODULE__
    # The reverse: the follow-up call(s) this lead spawned, if any.
    has_many :follow_ups, __MODULE__, foreign_key: :follow_up_of_id

    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses

  @doc false
  def create_changeset(lead, attrs) do
    lead
    |> cast(attrs, [
      :name,
      :phone,
      :source,
      :department_id,
      :department_name,
      :context,
      :goal,
      :follow_up_of_id
    ])
    |> validate_required([:name, :phone, :department_id])
    |> validate_format(:phone, ~r/^\+?[0-9\s\-\(\)]{7,20}$/,
      message: "must be a valid phone number"
    )
    |> foreign_key_constraint(:department_id)
    |> foreign_key_constraint(:follow_up_of_id)
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
      :status_message,
      :task_completed,
      :summary,
      :transcript,
      :error,
      :escalation_status,
      :escalation_reason,
      :suggested_follow_up_goal,
      :suggested_department_id
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:escalation_status, @escalation_statuses)
    |> foreign_key_constraint(:suggested_department_id)
  end

  def escalation_statuses, do: @escalation_statuses

  @default_purpose "Let them know you're reaching out to introduce yourself and see how you " <>
                     "can help. Ask if now is a good time to talk."

  defp put_default_goal(changeset) do
    case get_field(changeset, :goal) do
      nil ->
        name = get_field(changeset, :name)
        opening = opening_line(get_field(changeset, :department_name))
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
