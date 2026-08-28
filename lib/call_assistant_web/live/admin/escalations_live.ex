defmodule CallAssistantWeb.Admin.EscalationsLive do
  @moduledoc """
  Where the "notification" from `CallAssistant.Leads.Escalation` actually
  leads: calls flagged as needing an admin's attention, split into what
  still needs a human ("pending") and what the system already handled on
  its own ("auto_handled" - shown for visibility, not action).
  """

  use CallAssistantWeb, :live_view

  alias CallAssistant.Departments
  alias CallAssistant.Leads
  alias CallAssistant.Leads.Lead

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    if connected?(socket), do: Leads.subscribe(scope)

    {:ok,
     socket
     |> assign(:page_title, "Escalations")
     |> assign(:forms, %{})
     |> load()}
  end

  defp load(socket) do
    pending = Leads.list_pending_escalations()
    admin_department = Departments.admin_department()

    forms =
      Map.new(pending, fn lead ->
        department = lead.suggested_department || admin_department

        attrs = %{
          "name" => lead.name,
          "phone" => lead.phone,
          "goal" => lead.suggested_follow_up_goal,
          "department_id" => department.id
        }

        {lead.id, to_form(Leads.change_lead(%Lead{}, department, attrs), as: "lead_#{lead.id}")}
      end)

    socket
    |> assign(:admin_department, admin_department)
    |> assign(:departments, Departments.list_departments())
    |> assign(:pending, pending)
    |> assign(:auto_handled, Leads.list_auto_handled_escalations())
    |> update(:forms, &Map.merge(&1, forms))
  end

  @impl true
  def handle_event("validate_follow_up", %{"_target" => [param_name | _]} = params, socket) do
    lead_id = lead_id_from_param(param_name)
    attrs = Map.get(params, param_name, %{})
    department = resolve_department(attrs, socket.assigns.admin_department)

    form =
      %Lead{}
      |> Leads.change_lead(department, attrs)
      |> Map.put(:action, :validate)
      |> to_form(as: param_name)

    {:noreply, update(socket, :forms, &Map.put(&1, lead_id, form))}
  end

  # Unlike "validate_follow_up" (fired on phx-change, which LiveView always
  # tags with "_target"), a plain phx-submit carries no such key - the
  # form's own field data is the only thing in params, under one key (the
  # form's `as:` name), so that's what identifies which lead this is for.
  def handle_event("follow_up", params, socket) do
    [param_name] = Map.keys(params)
    lead_id = lead_id_from_param(param_name)
    attrs = Map.fetch!(params, param_name)
    department = resolve_department(attrs, socket.assigns.admin_department)

    case Leads.create_lead(department, Map.put(attrs, "follow_up_of_id", lead_id)) do
      {:ok, lead} ->
        Leads.resolve_escalation(lead_id)

        {:noreply,
         socket
         |> put_flash(:info, "Calling #{lead.name} now…")
         |> load()}

      {:error, changeset} ->
        {:noreply,
         update(socket, :forms, &Map.put(&1, lead_id, to_form(changeset, as: param_name)))}
    end
  end

  def handle_event("dismiss", %{"id" => id}, socket) do
    {:ok, _} = Leads.resolve_escalation(id)
    {:noreply, socket |> put_flash(:info, "Dismissed.") |> load()}
  end

  defp lead_id_from_param("lead_" <> id), do: id

  # Blank, invalid, or missing department all fall back to Admin rather
  # than a validation error - same reasoning as Admin.CallsLive's
  # resolve_department/2, and the id is only ever a value the admin
  # themself picked from the rendered <select>, resolved against a real
  # record here, never trusted as-is.
  defp resolve_department(%{"department_id" => id}, admin_department)
       when is_binary(id) and id != "" do
    case Integer.parse(id) do
      {id, _} -> Departments.get_department(id) || admin_department
      :error -> admin_department
    end
  end

  defp resolve_department(_attrs, admin_department), do: admin_department

  @impl true
  def handle_info({:lead_updated, _lead}, socket) do
    {:noreply, load(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={:escalations}>
      <div class="mx-auto max-w-4xl px-4 py-10 sm:px-6 lg:px-8">
        <header class="mb-8">
          <h1 class="text-2xl font-semibold tracking-tight text-base-content">Escalations</h1>
          <p class="mt-1.5 text-sm text-base-content/60">
            Calls a completed call flagged as needing your attention. CALL-E has no way to
            transfer a live call, so this is always a follow-up call, placed after the fact.
          </p>
        </header>

        <section class="mb-10">
          <h2 class="mb-3 text-sm font-semibold text-base-content">
            Needs your review <span class="text-base-content/40">({length(@pending)})</span>
          </h2>

          <div
            :if={@pending == []}
            class="rounded-xl border border-base-300 bg-base-100 p-8 text-center text-sm text-base-content/50"
          >
            Nothing waiting on you right now.
          </div>

          <div
            :for={lead <- @pending}
            class="mb-4 rounded-xl border border-base-300 bg-base-100 p-5 shadow-sm"
          >
            <div class="mb-3 flex items-start justify-between gap-4">
              <div>
                <div class="font-medium text-base-content">{lead.name}</div>
                <div class="text-sm text-base-content/60">
                  {lead.phone} · from {lead.department.name}
                </div>
              </div>
              <.link
                navigate={~p"/leads/#{lead.id}"}
                class="text-xs font-medium text-primary hover:underline"
              >
                View original call
              </.link>
            </div>

            <p class="mb-1 flex items-start gap-1.5 text-sm text-base-content/70">
              <.icon
                name="hero-exclamation-triangle-micro"
                class="mt-0.5 size-4 shrink-0 text-warning"
              />
              {lead.escalation_reason}
            </p>

            <p :if={lead.suggested_department} class="mb-4 pl-5 text-xs text-base-content/50">
              Classifier suggests routing the follow-up to
              <strong>{lead.suggested_department.name}</strong>
              instead.
            </p>

            <.form
              for={@forms[lead.id]}
              id={"follow-up-form-#{lead.id}"}
              phx-change="validate_follow_up"
              phx-submit="follow_up"
              class="space-y-3"
            >
              <input type="hidden" name={"lead_#{lead.id}[name]"} value={lead.name} />
              <input type="hidden" name={"lead_#{lead.id}[phone]"} value={lead.phone} />
              <.input
                field={@forms[lead.id][:department_id]}
                type="select"
                label="Follow-up department"
                options={Enum.map(@departments, &{&1.name, &1.id})}
              />
              <.input
                field={@forms[lead.id][:goal]}
                type="textarea"
                label="Follow-up call goal"
                rows="3"
              />
              <div class="flex justify-end gap-2">
                <button
                  type="button"
                  phx-click="dismiss"
                  phx-value-id={lead.id}
                  class="btn btn-ghost h-9"
                  data-confirm="Dismiss without placing a follow-up call?"
                >
                  Dismiss
                </button>
                <.button class="h-9">
                  <.icon name="hero-phone-arrow-up-right-micro" class="size-4" /> Place follow-up call
                </.button>
              </div>
            </.form>
          </div>
        </section>

        <section>
          <h2 class="mb-3 text-sm font-semibold text-base-content">
            Auto-handled <span class="text-base-content/40">({length(@auto_handled)})</span>
          </h2>
          <p class="mb-3 text-xs text-base-content/50">
            The system was confident enough to place these follow-ups on its own - shown here so
            nothing it did is invisible, not because they need action.
          </p>

          <div
            :if={@auto_handled == []}
            class="rounded-xl border border-base-300 bg-base-100 p-8 text-center text-sm text-base-content/50"
          >
            None yet.
          </div>

          <ul
            :if={@auto_handled != []}
            class="divide-y divide-base-300 rounded-xl border border-base-300 bg-base-100"
          >
            <li :for={lead <- @auto_handled} class="p-4 text-sm">
              <div class="mb-1 flex items-center justify-between">
                <span class="font-medium text-base-content">{lead.name}</span>
                <span class="text-xs text-base-content/40">{lead.department.name}</span>
              </div>
              <p class="mb-2 text-base-content/60">{lead.escalation_reason}</p>
              <.link
                :for={follow_up <- lead.follow_ups}
                navigate={~p"/leads/#{follow_up.id}"}
                class="inline-flex items-center gap-1 text-xs font-medium text-primary hover:underline"
              >
                View follow-up call to {follow_up.department.name}
                <.icon name="hero-arrow-right-micro" class="size-3.5" />
              </.link>
            </li>
          </ul>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
