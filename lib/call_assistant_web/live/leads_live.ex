defmodule CallAssistantWeb.LeadsLive do
  use CallAssistantWeb, :live_view

  alias CallAssistant.Leads
  alias CallAssistant.Leads.Lead

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Leads.subscribe()

    {:ok,
     socket
     |> assign(:page_title, "Speed-to-Lead")
     |> assign(:form, to_form(Leads.change_lead(%Lead{})))
     |> assign(:leads, Leads.list_leads())}
  end

  @impl true
  def handle_event("validate", %{"lead" => lead_params}, socket) do
    form =
      %Lead{}
      |> Leads.change_lead(lead_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"lead" => lead_params}, socket) do
    case Leads.create_lead(lead_params) do
      {:ok, lead} ->
        {:noreply,
         socket
         |> put_flash(:info, "Calling #{lead.name} now…")
         |> assign(:form, to_form(Leads.change_lead(%Lead{})))
         |> assign(:leads, [lead | socket.assigns.leads])}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
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

    {:noreply, assign(socket, :leads, leads)}
  end

  defp count_by(leads, statuses), do: Enum.count(leads, &(&1.status in statuses))

  defp in_flight_count(leads),
    do: count_by(leads, CallAssistantWeb.LeadComponents.in_flight_statuses())

  defp initials(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&String.first/1)
    |> Enum.take(2)
    |> Enum.join()
    |> String.upcase()
  end

  defp has_call_logs?(lead), do: lead.call_run_id != nil

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-5xl px-4 py-10 sm:px-6 lg:px-8">
        <header class="mb-8">
          <h1 class="text-2xl font-semibold tracking-tight text-base-content">Speed-to-Lead</h1>
          <p class="mt-1.5 max-w-2xl text-sm text-base-content/60">
            Add a lead and CALL-E calls them immediately to follow up — no more losing deals to
            slow follow-up. Each call's outcome and summary show up here the moment it ends.
          </p>
        </header>

        <div class="mb-8 grid grid-cols-2 gap-3 sm:grid-cols-4">
          <div class="rounded-xl border border-base-300 bg-base-100 px-4 py-3">
            <div class="text-xs font-medium text-base-content/50">Total leads</div>
            <div class="mt-1 text-xl font-semibold text-base-content">{length(@leads)}</div>
          </div>
          <div class="rounded-xl border border-base-300 bg-base-100 px-4 py-3">
            <div class="text-xs font-medium text-base-content/50">Calling now</div>
            <div class="mt-1 text-xl font-semibold text-info">
              {in_flight_count(@leads)}
            </div>
          </div>
          <div class="rounded-xl border border-base-300 bg-base-100 px-4 py-3">
            <div class="text-xs font-medium text-base-content/50">Completed</div>
            <div class="mt-1 text-xl font-semibold text-success">
              {count_by(@leads, ~w(completed))}
            </div>
          </div>
          <div class="rounded-xl border border-base-300 bg-base-100 px-4 py-3">
            <div class="text-xs font-medium text-base-content/50">No answer / declined</div>
            <div class="mt-1 text-xl font-semibold text-base-content/70">
              {count_by(@leads, ~w(no_answer declined failed))}
            </div>
          </div>
        </div>

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
              <div class="min-w-[12rem] flex-1">
                <.input
                  field={@form[:department]}
                  label="Department"
                  placeholder="e.g. Finance Office"
                  list="department-suggestions"
                />
                <datalist id="department-suggestions">
                  <option value="CEO's Office" />
                  <option value="Finance Office" />
                  <option value="Sales" />
                  <option value="Support" />
                  <option value="HR" />
                  <option value="Operations" />
                </datalist>
              </div>
            </div>

            <div>
              <.input
                field={@form[:context]}
                type="textarea"
                label="What's this call about?"
                placeholder="e.g. This is our first call to this client - introduce ourselves and ask about their current supplier. Or: let them know invoice #4521 is overdue and ask when they can settle it."
                rows="2"
              />
              <p class="mt-1.5 text-xs text-base-content/40">
                Opens with:
                <span class="font-medium">"{Lead.opening_line(@form[:department].value)}"</span>
                — leave blank for a generic introduction call.
              </p>
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
                  <div class="flex items-start gap-3">
                    <span class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full bg-primary/10 text-xs font-semibold text-primary">
                      {initials(lead.name)}
                    </span>
                    <div>
                      <div class="font-medium text-base-content">{lead.name}</div>
                      <div class="text-base-content/60">{lead.phone}</div>
                      <div class="text-xs text-base-content/40">
                        {lead.source}
                        <span :if={lead.department}>· {lead.department}</span>
                      </div>
                    </div>
                  </div>
                </td>
                <td class="px-4 py-3 align-top">
                  <.status_badge status={lead.status} />
                  <div :if={lead.status_message} class="mt-1 text-xs text-base-content/40">
                    {lead.status_message}
                  </div>
                </td>
                <td class="max-w-md px-4 py-3 align-top text-base-content/70">
                  <div
                    :if={lead.task_completed == true}
                    class="flex items-center gap-1 font-medium text-success"
                  >
                    <.icon name="hero-check-circle-micro" class="size-4" /> Goal achieved
                  </div>
                  <div
                    :if={lead.task_completed == false}
                    class="flex items-center gap-1 font-medium text-base-content/50"
                  >
                    <.icon name="hero-minus-circle-micro" class="size-4" /> Goal not achieved
                  </div>
                  <div :if={lead.summary} class="mt-0.5">{lead.summary}</div>
                  <div :if={lead.error} class="mt-0.5 flex items-center gap-1 text-error">
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
                <td colspan="4" class="px-4 py-16 text-center">
                  <.icon name="hero-phone" class="mx-auto size-8 text-base-content/25" />
                  <p class="mt-3 text-sm text-base-content/50">
                    No leads yet — add one above to see CALL-E call them live.
                  </p>
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
