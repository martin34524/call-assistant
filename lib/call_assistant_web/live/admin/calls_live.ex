defmodule CallAssistantWeb.Admin.CallsLive do
  @moduledoc """
  The admin's own general calling page: every call across every
  department, and a form to place a new one for whichever department the
  admin picks. Without this, the only way an admin could place a call was
  by first drilling into one specific department's page
  (`CallAssistantWeb.Admin.DepartmentLive`) - this is the direct
  equivalent of a member's own dashboard, just department-picking instead
  of department-implicit.
  """

  use CallAssistantWeb, :live_view

  alias CallAssistant.Departments
  alias CallAssistant.Leads
  alias CallAssistant.Leads.Lead

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    if connected?(socket), do: Leads.subscribe(scope)
    admin_department = Departments.admin_department()

    {:ok,
     socket
     |> assign(:page_title, "Calls")
     |> assign(:admin_department, admin_department)
     |> assign(:departments, Departments.list_departments())
     |> assign(:form, to_form(default_changeset(admin_department)))
     |> assign(:leads, Leads.list_leads(scope))
     |> assign(:tracking_flash_for, nil)}
  end

  defp default_changeset(admin_department) do
    Leads.change_lead(%Lead{}, admin_department)
  end

  @impl true
  def handle_event("validate", %{"lead" => params}, socket) do
    department = resolve_department(params, socket.assigns.admin_department)

    changeset =
      %Lead{}
      |> Leads.change_lead(department, params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"lead" => params}, socket) do
    department = resolve_department(params, socket.assigns.admin_department)

    case Leads.create_lead(department, params) do
      {:ok, lead} ->
        {:noreply,
         socket
         |> put_flash(:info, "Calling #{lead.name} now…")
         |> assign(:tracking_flash_for, lead.id)
         |> assign(:form, to_form(default_changeset(socket.assigns.admin_department)))
         |> assign(:leads, [lead | socket.assigns.leads])}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("cancel_call", %{"id" => id}, socket) do
    Leads.cancel(socket.assigns.current_scope, id)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:lead_updated, updated_lead}, socket) do
    leads =
      Enum.map(socket.assigns.leads, fn lead ->
        if lead.id == updated_lead.id, do: updated_lead, else: lead
      end)

    leads =
      if Enum.any?(leads, &(&1.id == updated_lead.id)),
        do: leads,
        else: [updated_lead | leads]

    socket =
      if socket.assigns.tracking_flash_for == updated_lead.id and
           CallAssistantWeb.LeadComponents.settled?(updated_lead.status) do
        socket |> clear_flash(:info) |> assign(:tracking_flash_for, nil)
      else
        socket
      end

    {:noreply, assign(socket, :leads, leads)}
  end

  # Department is optional on this page - blank, invalid, or missing all
  # fall back to the admin's own department rather than a validation
  # error, since "who is this call for" shouldn't block an admin from
  # just placing a call.
  defp resolve_department(%{"department_id" => id}, admin_department)
       when is_binary(id) and id != "" do
    case Integer.parse(id) do
      {id, _} -> Departments.get_department(id) || admin_department
      :error -> admin_department
    end
  end

  defp resolve_department(_params, admin_department), do: admin_department

  defp has_call_logs?(lead), do: lead.call_run_id != nil

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={:calls}>
      <div class="mx-auto max-w-5xl px-4 py-10 sm:px-6 lg:px-8">
        <header class="mb-8">
          <h1 class="text-2xl font-semibold tracking-tight text-base-content">Calls</h1>
          <p class="mt-1.5 text-sm text-base-content/60">
            Every call across every department. Defaults to your own Admin calls - only change
            the department if this one's on behalf of another team.
          </p>
        </header>

        <div class="mb-8 rounded-xl border border-base-300 bg-base-100 p-5 shadow-sm">
          <.form
            for={@form}
            id="new-call-form"
            phx-change="validate"
            phx-submit="save"
            class="space-y-4"
          >
            <div class="flex flex-wrap items-end gap-4">
              <div class="min-w-[10rem] flex-1">
                <.input
                  field={@form[:department_id]}
                  type="select"
                  label="Department"
                  prompt="Choose a department"
                  options={Enum.map(@departments, &{&1.name, &1.id})}
                />
              </div>
              <div class="min-w-[10rem] flex-1">
                <.input field={@form[:name]} label="Name" placeholder="Jordan Lee" />
              </div>
              <div class="min-w-[10rem] flex-1">
                <.input field={@form[:phone]} label="Phone" placeholder="+1 555 123 4567" />
              </div>
              <div class="min-w-[10rem] flex-1">
                <.input
                  field={@form[:source]}
                  type="select"
                  label="Source"
                  options={["Website form", "Missed call", "Referral", "Other"]}
                />
              </div>
            </div>
            <div>
              <.input
                field={@form[:context]}
                type="textarea"
                label="What's this call about?"
                placeholder="e.g. Let them know invoice #4521 is overdue and ask when they can settle it."
                rows="2"
              />
            </div>
            <div class="flex justify-end">
              <.button class="h-10">
                <.icon name="hero-phone-arrow-up-right-micro" class="size-4" /> Call now
              </.button>
            </div>
          </.form>
        </div>

        <div class="overflow-hidden rounded-xl border border-base-300 bg-base-100 shadow-sm">
          <table class="min-w-full divide-y divide-base-300 text-sm">
            <thead class="bg-base-200/60 text-left text-xs font-medium tracking-wide text-base-content/50 uppercase">
              <tr>
                <th class="px-4 py-3">Lead</th>
                <th class="px-4 py-3">Department</th>
                <th class="px-4 py-3">Status</th>
                <th class="px-4 py-3">Outcome</th>
                <th class="px-4 py-3"></th>
              </tr>
            </thead>
            <tbody class="divide-y divide-base-300">
              <tr
                :for={lead <- @leads}
                id={"lead-#{lead.id}"}
                class="transition-colors hover:bg-base-200/40"
              >
                <td class="px-4 py-3 align-top">
                  <div class="font-medium text-base-content">{lead.name}</div>
                  <div class="text-base-content/60">{lead.phone}</div>
                </td>
                <td class="px-4 py-3 align-top text-base-content/70">
                  {lead.department.name}
                </td>
                <td class="px-4 py-3 align-top">
                  <.status_badge status={lead.status} />
                  <div :if={lead.status_message} class="mt-1 text-xs text-base-content/40">
                    {lead.status_message}
                  </div>
                </td>
                <td class="max-w-md px-4 py-3 align-top text-base-content/70">
                  <div :if={lead.summary}>{lead.summary}</div>
                  <div :if={lead.error} class="flex items-center gap-1 text-error">
                    <.icon name="hero-exclamation-triangle-micro" class="size-4" /> {lead.error}
                  </div>
                </td>
                <td class="px-4 py-3 align-top text-right">
                  <div class="flex flex-col items-end gap-1">
                    <.cancel_button lead={lead} />
                    <.link
                      :if={has_call_logs?(lead)}
                      navigate={~p"/leads/#{lead.id}"}
                      class="inline-flex items-center gap-1 text-xs font-medium text-primary hover:underline"
                    >
                      View call logs <.icon name="hero-arrow-right-micro" class="size-3.5" />
                    </.link>
                  </div>
                </td>
              </tr>
              <tr :if={@leads == []}>
                <td colspan="5" class="px-4 py-16 text-center text-sm text-base-content/50">
                  No calls yet — place one above.
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
