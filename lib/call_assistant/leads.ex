defmodule CallAssistant.Leads do
  @moduledoc """
  Context for managing leads and kicking off CALL-E qualification calls.

  Reads (`list_leads/1`, `get_lead!/2`, `calls_today/1`, `subscribe/1`)
  are scoped: a `%CallAssistant.Accounts.Scope{}` is the first argument,
  and a "member" scope only ever sees its own department's leads - this
  is the actual access boundary between departments, not just the router
  requiring login.

  Writes (`create_lead/2`, `change_lead/3`) take an already-resolved
  `%CallAssistant.Departments.Department{}` instead of a scope, because
  every call site already knows exactly which department a lead belongs
  to before calling in - `CallAssistantWeb.LeadsLive` uses the current
  member's own department, `CallAssistantWeb.Admin.DepartmentLive` uses
  whichever department the (admin-only) URL names. Neither ever takes a
  department from raw form params, so there's nothing to tamper with.
  """

  import Ecto.Query, warn: false

  alias CallAssistant.Accounts.Scope
  alias CallAssistant.Departments.Department
  alias CallAssistant.Repo
  alias CallAssistant.Leads.{Lead, Qualifier}

  @all_topic "leads:all"

  defp department_topic(department_id), do: "leads:department:#{department_id}"

  @doc """
  Subscribes to lead updates visible to this scope: every department for
  an admin, only the caller's own department for a member. Broadcasting
  (see `broadcast/1`) publishes to both the department-specific topic and
  the admin-wide one, so a member's LiveView process never even receives
  a PubSub message about another department's lead - not just filtered
  out client-side, never delivered at all.
  """
  def subscribe(scope) do
    topic =
      if Scope.admin?(scope), do: @all_topic, else: department_topic(Scope.department_id(scope))

    Phoenix.PubSub.subscribe(CallAssistant.PubSub, topic)
  end

  def list_leads(scope) do
    scope
    |> scoped_query()
    |> order_by([l], desc: l.inserted_at)
    |> preload(:department)
    |> Repo.all()
  end

  @doc """
  Raises `Ecto.NoResultsError` (Phoenix turns this into a 404) if the
  lead doesn't exist *or* isn't visible to this scope - a member can't
  view another department's lead by guessing its id.
  """
  def get_lead!(scope, id) do
    scope
    |> scoped_query()
    |> preload(:department)
    |> Repo.get!(id)
  end

  @doc """
  Marks a lead as cancelled - the closest honest equivalent to "end this
  call" that CALL-E's actual API supports. CALL-E has no cancel/hangup
  tool (only plan_call/run_call/get_call_run), so this does not - cannot
  - terminate a real in-progress phone call; CALL-E keeps running it to
  completion on its own regardless. What this genuinely does: tells
  `CallAssistant.Leads.Qualifier` to stop polling and stop writing
  further updates to this lead, so the app stops tracking/displaying it
  as active. Raises `Ecto.NoResultsError` if the lead isn't visible to
  this scope, same as `get_lead!/2`.
  """
  def cancel(scope, id) do
    lead = get_lead!(scope, id)

    update_lead(lead, %{
      status: "cancelled",
      status_message: "Stopped tracking - CALL-E may still complete this call on its own."
    })
  end

  @doc false
  # Internal, unscoped: lets CallAssistant.Leads.Qualifier check between
  # polls whether a lead was cancelled out from under it, without
  # threading a scope through the whole background task.
  def current_status(lead_id), do: Repo.get(Lead, lead_id) |> then(&(&1 && &1.status))

  defp scoped_query(scope) do
    if Scope.admin?(scope) do
      from(l in Lead)
    else
      from(l in Lead, where: l.department_id == ^Scope.department_id(scope))
    end
  end

  @doc "Counts leads in this scope where a call was actually placed today (UTC)."
  def calls_today(scope) do
    scope |> scoped_query() |> where_call_placed_today() |> Repo.aggregate(:count)
  end

  defp where_call_placed_today(query) do
    today = Date.utc_today()

    query
    |> where([l], not is_nil(l.call_run_id))
    |> where([l], l.inserted_at >= ^DateTime.new!(today, ~T[00:00:00]))
  end

  @doc "Admin-only: every lead in one specific department, for the admin's drill-down page."
  def list_leads_for_department(department_id) do
    Lead
    |> where([l], l.department_id == ^department_id)
    |> order_by([l], desc: l.inserted_at)
    |> preload(:department)
    |> Repo.all()
  end

  @doc """
  Admin-only: `%{department_id => count}` of leads with a call placed
  today (UTC), across every department, for the admin overview.
  """
  def count_calls_today_by_department do
    Lead
    |> where_call_placed_today()
    |> group_by([l], l.department_id)
    |> select([l], {l.department_id, count(l.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Admin-only: `%{department_id => count}` of leads ever created, across every department."
  def count_leads_by_department do
    Lead
    |> group_by([l], l.department_id)
    |> select([l], {l.department_id, count(l.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Counts leads in this scope grouped by status, for the Reports page."
  def status_breakdown(scope) do
    scope
    |> scoped_query()
    |> group_by([l], l.status)
    |> select([l], {l.status, count(l.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Counts leads in this scope whose call achieved its stated goal."
  def count_task_completed(scope) do
    scope |> scoped_query() |> where([l], l.task_completed == true) |> Repo.aggregate(:count)
  end

  @doc """
  Admin-only: `%{department_id => %{status => count}}` across every
  department, for the admin Reports page.
  """
  def status_breakdown_by_department do
    Lead
    |> group_by([l], [l.department_id, l.status])
    |> select([l], {l.department_id, l.status, count(l.id)})
    |> Repo.all()
    |> Enum.group_by(fn {department_id, _status, _count} -> department_id end, fn {_, s, c} ->
      {s, c}
    end)
    |> Map.new(fn {department_id, pairs} -> {department_id, Map.new(pairs)} end)
  end

  @doc """
  Creates a lead in `department` and immediately kicks off the CALL-E
  qualification call in the background (speed-to-lead: call within
  seconds of intake).
  """
  def create_lead(%Department{} = department, attrs) do
    with {:ok, lead} <-
           %Lead{}
           |> Lead.create_changeset(with_department(attrs, department))
           |> Repo.insert() do
      lead = Repo.preload(lead, :department)
      broadcast(lead)
      Qualifier.start(lead)
      {:ok, lead}
    end
  end

  def change_lead(%Lead{} = lead, %Department{} = department, attrs \\ %{}) do
    Lead.create_changeset(lead, with_department(attrs, department))
  end

  defp with_department(attrs, %Department{} = department) do
    attrs
    |> Map.put("department_id", department.id)
    |> Map.put("department_name", department.name)
  end

  def update_lead(%Lead{} = lead, attrs) do
    with {:ok, lead} <-
           lead
           |> Lead.update_changeset(attrs)
           |> Repo.update() do
      lead = Repo.preload(lead, :department)
      broadcast(lead)
      {:ok, lead}
    end
  end

  defp broadcast(%Lead{} = lead) do
    Phoenix.PubSub.broadcast(
      CallAssistant.PubSub,
      department_topic(lead.department_id),
      {:lead_updated, lead}
    )

    Phoenix.PubSub.broadcast(CallAssistant.PubSub, @all_topic, {:lead_updated, lead})
    lead
  end
end
