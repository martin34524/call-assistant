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

  defp status_badge(status) do
    {label, classes} =
      case status do
        "new" -> {"New", "bg-zinc-100 text-zinc-700"}
        "planning" -> {"Planning call", "bg-amber-100 text-amber-800"}
        "needs_clarification" -> {"Needs more info", "bg-orange-100 text-orange-800"}
        "ready_to_run" -> {"Dialing", "bg-amber-100 text-amber-800"}
        "in_progress" -> {"Call in progress", "bg-blue-100 text-blue-800"}
        "completed" -> {"Completed", "bg-green-100 text-green-800"}
        "declined" -> {"Declined", "bg-zinc-100 text-zinc-600"}
        "no_answer" -> {"No answer", "bg-zinc-100 text-zinc-600"}
        "failed" -> {"Failed", "bg-red-100 text-red-800"}
        other -> {other, "bg-zinc-100 text-zinc-700"}
      end

    assigns = %{label: label, classes: classes}

    ~H"""
    <span class={"inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium #{@classes}"}>
      <%= if @label in ["Planning call", "Dialing", "Call in progress"] do %>
        <svg class="mr-1 -ml-0.5 h-2 w-2 animate-pulse" fill="currentColor" viewBox="0 0 8 8">
          <circle cx="4" cy="4" r="3" />
        </svg>
      <% end %>
      {@label}
    </span>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-5xl px-4 py-10">
        <header class="mb-8">
          <h1 class="text-2xl font-semibold text-zinc-900">Speed-to-Lead</h1>
          <p class="mt-1 text-sm text-zinc-500">
            Add a lead and CALL-E calls them immediately to follow up — no more losing deals to
            slow follow-up. Each call's outcome and summary show up here as soon as it ends.
          </p>
        </header>

        <div class="mb-10 rounded-lg border border-zinc-200 bg-white p-5 shadow-sm">
          <.form
            for={@form}
            id="new-lead-form"
            phx-change="validate"
            phx-submit="save"
            class="flex flex-wrap items-end gap-4"
          >
            <div class="flex-1 min-w-[10rem]">
              <.input field={@form[:name]} label="Name" placeholder="Jordan Lee" />
            </div>
            <div class="flex-1 min-w-[10rem]">
              <.input field={@form[:phone]} label="Phone" placeholder="+1 555 123 4567" />
            </div>
            <div class="flex-1 min-w-[10rem]">
              <.input
                field={@form[:source]}
                type="select"
                label="Source"
                options={["Website form", "Missed call", "Referral", "Other"]}
              />
            </div>
            <.button class="h-10">Call now</.button>
          </.form>
        </div>

        <div class="overflow-hidden rounded-lg border border-zinc-200 bg-white shadow-sm">
          <table class="min-w-full divide-y divide-zinc-200 text-sm">
            <thead class="bg-zinc-50 text-left text-xs font-medium uppercase tracking-wide text-zinc-500">
              <tr>
                <th class="px-4 py-3">Lead</th>
                <th class="px-4 py-3">Status</th>
                <th class="px-4 py-3">Outcome</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-zinc-100">
              <tr :for={lead <- @leads} id={"lead-#{lead.id}"}>
                <td class="px-4 py-3 align-top">
                  <div class="font-medium text-zinc-900">{lead.name}</div>
                  <div class="text-zinc-500">{lead.phone}</div>
                  <div class="text-xs text-zinc-400">{lead.source}</div>
                </td>
                <td class="px-4 py-3 align-top">{status_badge(lead.status)}</td>
                <td class="px-4 py-3 align-top max-w-md text-zinc-600">
                  <div :if={lead.task_completed == true} class="text-green-700 font-medium">
                    Goal achieved
                  </div>
                  <div :if={lead.task_completed == false} class="text-zinc-500 font-medium">
                    Goal not achieved
                  </div>
                  <div :if={lead.summary}>{lead.summary}</div>
                  <div :if={lead.error} class="text-red-600">{lead.error}</div>
                </td>
              </tr>
              <tr :if={@leads == []}>
                <td colspan="3" class="px-4 py-10 text-center text-zinc-400">
                  No leads yet — add one above to see CALL-E call them live.
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
