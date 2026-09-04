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
  Voice-command contact lookup (see `CallAssistant.VoiceCommand`): leads
  visible to this scope whose name matches `name` - case-insensitive exact
  match first, falling back to a "contains" match if nothing matched
  exactly - collapsed to distinct phone numbers (ignoring formatting) so
  someone called multiple times under the same name only surfaces once
  unless they genuinely have different numbers on file. Same access
  boundary as everything else here: a member only ever matches against
  their own department's leads.
  """
  def find_matching_contacts(scope, name) do
    normalized = String.trim(name)

    case matching_leads(scope, normalized, :exact) do
      [] -> matching_leads(scope, normalized, :contains)
      exact -> exact
    end
    |> dedupe_by_phone()
  end

  defp matching_leads(scope, name, :exact) do
    scope
    |> scoped_query()
    |> where([l], ilike(l.name, ^name))
    |> select([l], %{name: l.name, phone: l.phone})
    |> Repo.all()
  end

  defp matching_leads(scope, name, :contains) do
    scope
    |> scoped_query()
    |> where([l], ilike(l.name, ^"%#{name}%"))
    |> select([l], %{name: l.name, phone: l.phone})
    |> Repo.all()
  end

  defp dedupe_by_phone(contacts) do
    Enum.uniq_by(contacts, fn %{phone: phone} -> normalize_phone(phone) end)
  end

  defp normalize_phone(phone), do: Regex.replace(~r/\D/, phone, "")

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

    message =
      if lead.call_run_id do
        "Stopped tracking - CALL-E may still complete this call on its own."
      else
        "Cancelled before the call was placed."
      end

    update_lead(lead, %{status: "cancelled", status_message: message})
  end

  @doc false
  # Internal, unscoped: lets CallAssistant.Leads.Qualifier check between
  # polls whether a lead was cancelled out from under it, without
  # threading a scope through the whole background task.
  def current_status(lead_id), do: Repo.get(Lead, lead_id) |> then(&(&1 && &1.status))

  @doc """
  Admin-only: how many calls are currently scheduled for later - backs a
  small count on the admin overview, same shape as
  `count_pending_escalations/0`.
  """
  def count_scheduled do
    Repo.aggregate(from(l in Lead, where: l.status == "scheduled"), :count)
  end

  @doc false
  # Internal, unscoped: CallAssistant.Leads.Scheduler polls this and calls
  # Qualifier.start/1 on whatever comes back - the same call create_lead/2
  # already makes for an immediate call, so from here on a scheduled
  # call's lifecycle is indistinguishable from a normal one. A cancelled
  # scheduled call simply never matches this query again.
  def list_due_scheduled_leads do
    now = DateTime.utc_now()

    Lead
    |> where([l], l.status == "scheduled" and l.scheduled_at <= ^now)
    |> preload(:department)
    |> Repo.all()
  end

  @doc """
  Finds every due scheduled lead and places its call - the poller
  (`CallAssistant.Leads.Scheduler`) calls this on a timer; kept as a plain
  function so it's testable with no GenServer timing involved.
  """
  def place_due_scheduled_calls do
    Enum.each(list_due_scheduled_leads(), &Qualifier.start/1)
  end

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
  Admin-only: how many leads need an admin's review right now - backs
  the sidebar badge (`CallAssistantWeb.Layouts.nav_items/1`). Deliberately
  excludes "auto_handled" - nothing is waiting on a human for those.
  """
  def count_pending_escalations do
    Repo.aggregate(from(l in Lead, where: l.escalation_status == "pending"), :count)
  end

  @doc "Admin-only: every lead awaiting review, oldest first (first flagged, first reviewed)."
  def list_pending_escalations do
    Lead
    |> where([l], l.escalation_status == "pending")
    |> order_by([l], asc: l.updated_at)
    |> preload([:department, :suggested_department])
    |> Repo.all()
  end

  @doc """
  Admin-only: every lead the system followed up on by itself, most
  recent first, with the follow-up call(s) it spawned preloaded (see
  `CallAssistant.Leads.Escalation.auto_handle/2`) - an audit trail, not
  an action queue.
  """
  def list_auto_handled_escalations do
    Lead
    |> where([l], l.escalation_status == "auto_handled")
    |> order_by([l], desc: l.updated_at)
    |> preload([:department, follow_ups: :department])
    |> Repo.all()
  end

  @doc """
  Admin-only: marks a "pending" escalation as resolved - either because
  the admin placed a follow-up call from the review form, or dismissed
  it as handled some other way. Raises `Ecto.NoResultsError` if `id`
  isn't a real lead (there's no scope check here since this is
  admin-only, enforced by the router, not by department).
  """
  def resolve_escalation(id) do
    Lead |> Repo.get!(id) |> update_lead(%{escalation_status: "resolved"})
  end

  @doc """
  Creates a lead in `department`. Kicks off the CALL-E qualification call
  in the background immediately (speed-to-lead: call within seconds of
  intake) - unless `attrs` set a future `scheduled_at`, in which case it's
  left alone for `CallAssistant.Leads.Scheduler` to pick up when due.
  """
  def create_lead(%Department{} = department, attrs) do
    with {:ok, lead} <-
           %Lead{}
           |> Lead.create_changeset(with_department(attrs, department))
           |> Repo.insert() do
      lead = Repo.preload(lead, :department)
      broadcast(lead)
      if is_nil(lead.scheduled_at), do: Qualifier.start(lead)
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
