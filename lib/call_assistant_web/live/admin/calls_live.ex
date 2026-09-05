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
  alias CallAssistant.VoiceCommand
  alias CallAssistantWeb.LeadComponents
  alias CallAssistantWeb.VoiceCommandComponents

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
     |> assign(:tracking_flash_for, nil)
     |> assign(:search, "")
     |> assign(:redial, nil)
     |> voice_reset()}
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
         |> place_call_success(lead)
         |> assign(:form, to_form(default_changeset(socket.assigns.admin_department)))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("cancel_call", %{"id" => id}, socket) do
    Leads.cancel(socket.assigns.current_scope, id)
    {:noreply, socket}
  end

  def handle_event("start_redial", %{"id" => id}, socket) do
    lead = Leads.get_lead!(socket.assigns.current_scope, id)
    form = to_form(%{"context" => lead.context || ""}, as: "redial")
    {:noreply, assign(socket, :redial, %{lead: lead, form: form})}
  end

  def handle_event("cancel_redial", _params, socket) do
    {:noreply, assign(socket, :redial, nil)}
  end

  def handle_event("confirm_redial", %{"redial" => %{"context" => context}}, socket) do
    case Leads.redial(socket.assigns.current_scope, socket.assigns.redial.lead.id, context) do
      {:ok, lead} ->
        {:noreply, socket |> assign(:redial, nil) |> place_call_success(lead)}

      {:error, _changeset} ->
        {:noreply,
         socket |> assign(:redial, nil) |> put_flash(:error, "Couldn't redial that lead.")}
    end
  end

  def handle_event("search", %{"q" => query}, socket) do
    {:noreply, assign(socket, :search, query)}
  end

  def handle_event("voice_start", _params, socket) do
    {:noreply,
     socket
     |> voice_reset()
     |> assign(:voice_step, :awaiting_command)
     |> voice_listen("Who do you want to call?")}
  end

  def handle_event("voice_cancel", _params, socket) do
    {:noreply, socket |> voice_reset() |> voice_stop()}
  end

  def handle_event("voice_recognition_error", %{"reason" => reason}, socket) do
    {:noreply,
     socket
     |> voice_reset()
     |> assign(:voice_error, voice_error_message(reason))
     |> voice_stop()}
  end

  def handle_event("voice_pick_candidate", %{"index" => index}, socket) do
    candidate = Enum.at(socket.assigns.voice_candidates, String.to_integer(index))

    {:noreply,
     socket
     |> assign(:voice_phone, candidate.phone)
     |> assign(:voice_candidates, [])
     |> assign(:voice_step, :awaiting_context)
     |> voice_listen("What's this call about?")}
  end

  def handle_event("voice_confirm", _params, socket) do
    {:noreply, voice_place_call(socket)}
  end

  def handle_event("voice_transcript", %{"text" => text}, socket) do
    {:noreply, handle_voice_transcript(socket, socket.assigns.voice_step, text)}
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

  defp place_call_success(socket, lead) do
    message =
      if lead.scheduled_at do
        "#{lead.name} is scheduled for #{LeadComponents.format_scheduled_at(lead.scheduled_at)}."
      else
        "Calling #{lead.name} now…"
      end

    socket
    |> put_flash(:info, message)
    |> assign(:tracking_flash_for, if(lead.scheduled_at, do: nil, else: lead.id))
    |> assign(:leads, [lead | socket.assigns.leads])
  end

  defp handle_voice_transcript(socket, :awaiting_command, text) do
    case VoiceCommand.parse_call_command(text) do
      {:ok, name} ->
        voice_resolve_contact(socket, name)

      :no_match ->
        socket
        |> assign(:voice_error, "Didn't catch a name to call - try \"Call Jane.\"")
        |> voice_listen("Who do you want to call?")
    end
  end

  defp handle_voice_transcript(socket, :awaiting_phone, text) do
    case VoiceCommand.extract_phone(text) do
      {:ok, phone} ->
        socket
        |> assign(:voice_phone, phone)
        |> assign(:voice_step, :awaiting_context)
        |> voice_listen("What's this call about?")

      :no_match ->
        socket
        |> assign(:voice_error, "Didn't catch a phone number - try again.")
        |> voice_listen("What's their phone number?")
    end
  end

  defp handle_voice_transcript(socket, :awaiting_context, text) do
    name = socket.assigns.voice_name
    phone = socket.assigns.voice_phone

    socket
    |> assign(:voice_context, text)
    |> assign(:voice_step, :confirming)
    |> voice_listen(
      "Call #{name} at #{phone} about: #{text}. Say yes to confirm, or no to cancel."
    )
  end

  defp handle_voice_transcript(socket, :confirming, text) do
    cond do
      VoiceCommand.affirmative?(text) ->
        voice_place_call(socket)

      VoiceCommand.negative?(text) ->
        socket |> voice_reset() |> voice_stop()

      true ->
        socket
        |> assign(:voice_error, "Didn't catch that - say \"yes\" to place the call.")
        |> voice_listen("Say yes to confirm, or no to cancel.")
    end
  end

  defp handle_voice_transcript(socket, _step, _text), do: socket

  defp voice_resolve_contact(socket, name) do
    case Leads.find_matching_contacts(socket.assigns.current_scope, name) do
      [] ->
        socket
        |> assign(:voice_name, name)
        |> assign(:voice_step, :awaiting_phone)
        |> voice_listen("I don't have a number for #{name}. What's their phone number?")

      [contact] ->
        socket
        |> assign(:voice_name, name)
        |> assign(:voice_phone, contact.phone)
        |> assign(:voice_step, :awaiting_context)
        |> voice_listen("What's this call about?")

      candidates ->
        socket
        |> assign(:voice_name, name)
        |> assign(:voice_candidates, candidates)
        |> assign(:voice_step, :disambiguating)
        |> voice_stop()
    end
  end

  # Voice-placed calls always land in the admin's own department, same as
  # the typed form's default - no voice-driven department picking in this
  # iteration (use the form to place a call on behalf of another team).
  defp voice_place_call(socket) do
    attrs = %{
      "name" => socket.assigns.voice_name,
      "phone" => socket.assigns.voice_phone,
      "context" => socket.assigns.voice_context
    }

    case Leads.create_lead(socket.assigns.admin_department, attrs) do
      {:ok, lead} ->
        socket
        |> place_call_success(lead)
        |> voice_reset()
        |> voice_stop()

      {:error, _changeset} ->
        socket
        |> voice_reset()
        |> assign(
          :voice_error,
          "Couldn't place that call - check the name/phone and try the form instead."
        )
        |> voice_stop()
    end
  end

  defp voice_reset(socket) do
    socket
    |> assign(:voice_step, :idle)
    |> assign(:voice_name, nil)
    |> assign(:voice_phone, nil)
    |> assign(:voice_context, nil)
    |> assign(:voice_candidates, [])
    |> assign(:voice_error, nil)
  end

  defp voice_listen(socket, prompt), do: push_event(socket, "voice_listen", %{prompt: prompt})
  defp voice_stop(socket), do: push_event(socket, "voice_stop", %{})

  defp voice_error_message("not-allowed"),
    do: "Microphone access was blocked - allow it and try again."

  defp voice_error_message("network"), do: "Voice recognition network error - try again."
  defp voice_error_message(_), do: "Voice recognition had a problem - try again."

  defp viewable?(lead), do: lead.call_run_id != nil or lead.status == "scheduled"

  defp view_label(lead),
    do: if(lead.status == "scheduled", do: "View details", else: "View call logs")

  defp scheduling?(form), do: form[:scheduled_at].value not in [nil, ""]

  defp filter_leads(leads, ""), do: leads

  defp filter_leads(leads, query) do
    query = String.downcase(query)

    Enum.filter(leads, fn lead ->
      String.contains?(String.downcase(lead.name), query) or
        String.contains?(lead.phone, query)
    end)
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :filtered_leads, filter_leads(assigns.leads, assigns.search))

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

        <VoiceCommandComponents.panel
          voice_step={@voice_step}
          voice_name={@voice_name}
          voice_phone={@voice_phone}
          voice_context={@voice_context}
          voice_candidates={@voice_candidates}
          voice_error={@voice_error}
        />

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
            <div class="max-w-xs">
              <.input
                field={@form[:scheduled_at]}
                type="datetime-local"
                label="Schedule for (optional)"
              />
              <p class="mt-1.5 text-xs text-base-content/40">
                Leave blank to call now. Times are your server's own clock.
              </p>
            </div>
            <div class="flex justify-end">
              <.button class="h-10">
                <.icon name="hero-phone-arrow-up-right-micro" class="size-4" />
                {if scheduling?(@form), do: "Schedule call", else: "Call now"}
              </.button>
            </div>
          </.form>
        </div>

        <form id="search-calls-form" phx-change="search" class="mb-3">
          <input
            type="text"
            name="q"
            value={@search}
            placeholder="Search calls by name or phone…"
            class="input input-bordered w-full max-w-xs"
            phx-debounce="200"
          />
        </form>

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
                :for={lead <- @filtered_leads}
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
                  <div :if={lead.scheduled_at} class="mt-1 text-xs text-base-content/40">
                    {LeadComponents.format_scheduled_at(lead.scheduled_at)}
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
                    <.redial_button lead={lead} />
                    <.link
                      :if={viewable?(lead)}
                      navigate={~p"/leads/#{lead.id}"}
                      class="inline-flex items-center gap-1 text-xs font-medium text-primary hover:underline"
                    >
                      {view_label(lead)} <.icon name="hero-arrow-right-micro" class="size-3.5" />
                    </.link>
                  </div>
                </td>
              </tr>
              <tr :if={@leads == []}>
                <td colspan="5" class="px-4 py-16 text-center text-sm text-base-content/50">
                  No calls yet — place one above.
                </td>
              </tr>
              <tr :if={@leads != [] and @filtered_leads == []}>
                <td colspan="5" class="px-4 py-16 text-center text-sm text-base-content/50">
                  No calls match "{@search}".
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <.redial_modal redial={@redial} />
    </Layouts.app>
    """
  end
end
