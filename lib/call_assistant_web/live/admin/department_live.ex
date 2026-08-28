defmodule CallAssistantWeb.Admin.DepartmentLive do
  @moduledoc """
  Admin drill-down into one department's calls - same list/create UI as
  the department's own dashboard (`CallAssistantWeb.LeadsLive`), reusing
  `CallAssistant.Leads.create_lead/2` and `CallAssistantWeb.LeadComponents`
  so both stay visually and behaviorally identical.
  """

  use CallAssistantWeb, :live_view

  alias CallAssistant.Departments
  alias CallAssistant.Leads
  alias CallAssistant.Leads.Lead

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    department = Departments.get_department!(id)

    if connected?(socket), do: Leads.subscribe(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:page_title, department.name)
     |> assign(:department, department)
     |> assign(:form, to_form(Leads.change_lead(%Lead{}, department)))
     |> assign(:leads, Leads.list_leads_for_department(department.id))}
  end

  @impl true
  def handle_event("validate", %{"lead" => lead_params}, socket) do
    form =
      %Lead{}
      |> Leads.change_lead(socket.assigns.department, lead_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"lead" => lead_params}, socket) do
    case Leads.create_lead(socket.assigns.department, lead_params) do
      {:ok, lead} ->
        {:noreply,
         socket
         |> put_flash(:info, "Calling #{lead.name} now…")
         |> assign(:form, to_form(Leads.change_lead(%Lead{}, socket.assigns.department)))
         |> assign(:leads, [lead | socket.assigns.leads])}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def handle_info({:lead_updated, updated_lead}, socket) do
    # The admin scope subscribes to every department's updates - only
    # merge the ones that belong to the department this page is showing.
    socket =
      if updated_lead.department_id == socket.assigns.department.id do
        leads =
          Enum.map(socket.assigns.leads, fn lead ->
            if lead.id == updated_lead.id, do: updated_lead, else: lead
          end)

        leads =
          if Enum.any?(leads, &(&1.id == updated_lead.id)),
            do: leads,
            else: [updated_lead | leads]

        assign(socket, :leads, leads)
      else
        socket
      end

    {:noreply, socket}
  end

  defp has_call_logs?(lead), do: lead.call_run_id != nil

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-5xl px-4 py-10 sm:px-6 lg:px-8">
        <.link
          navigate={~p"/admin"}
          class="inline-flex items-center gap-1 text-sm text-base-content/50 hover:text-base-content"
        >
          <.icon name="hero-arrow-left-micro" class="size-4" /> Back to admin
        </.link>

        <header class="mt-4 mb-8">
          <h1 class="text-2xl font-semibold tracking-tight text-base-content">{@department.name}</h1>
          <p class="mt-1.5 text-sm text-base-content/60">{length(@leads)} total leads</p>
        </header>

        <div class="mb-8 rounded-xl border border-base-300 bg-base-100 p-5 shadow-sm">
          <.form
            for={@form}
            id="new-lead-form"
            phx-change="validate"
            phx-submit="save"
            class="space-y-4"
          >
            <div class="flex flex-wrap items-end gap-4">
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
                  <div class="text-xs text-base-content/40">{lead.source}</div>
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
                  <.link
                    :if={has_call_logs?(lead)}
                    navigate={~p"/leads/#{lead.id}"}
                    class="inline-flex items-center gap-1 text-xs font-medium text-primary hover:underline"
                  >
                    View call logs <.icon name="hero-arrow-right-micro" class="size-3.5" />
                  </.link>
                </td>
              </tr>
              <tr :if={@leads == []}>
                <td colspan="4" class="px-4 py-16 text-center text-sm text-base-content/50">
                  No leads yet for this department.
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
