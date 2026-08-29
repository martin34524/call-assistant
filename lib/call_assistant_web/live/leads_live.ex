defmodule CallAssistantWeb.LeadsLive do
  use CallAssistantWeb, :live_view

  alias CallAssistant.Accounts.Scope
  alias CallAssistant.Departments
  alias CallAssistant.Leads
  alias CallAssistant.Leads.Lead
  alias CallAssistant.VoiceCommand
  alias CallAssistantWeb.VoiceCommandComponents

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    cond do
      Scope.admin?(scope) ->
        {:ok, redirect(socket, to: ~p"/admin")}

      # A member with no department assigned yet - shouldn't happen via
      # the admin's "+ New user" form (department is required there), but
      # is a real state a directly-created account could be in.
      is_nil(Scope.department_id(scope)) ->
        {:ok, assign(socket, page_title: "Speed-to-Lead", department: nil)}

      true ->
        if connected?(socket), do: Leads.subscribe(scope)

        department = Departments.get_department!(Scope.department_id(scope))

        {:ok,
         socket
         |> assign(:page_title, "Speed-to-Lead")
         |> assign(:department, department)
         |> assign(:form, to_form(Leads.change_lead(%Lead{}, department)))
         |> assign(:leads, Leads.list_leads(scope))
         |> assign(:calls_today, Leads.calls_today(scope))
         |> assign(:tracking_flash_for, nil)
         |> voice_reset()}
    end
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
         |> place_call_success(lead)
         |> assign(:form, to_form(Leads.change_lead(%Lead{}, socket.assigns.department)))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("cancel_call", %{"id" => id}, socket) do
    Leads.cancel(socket.assigns.current_scope, id)
    {:noreply, socket}
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

    {:noreply,
     assign(socket, leads: leads, calls_today: Leads.calls_today(socket.assigns.current_scope))}
  end

  defp place_call_success(socket, lead) do
    socket
    |> put_flash(:info, "Calling #{lead.name} now…")
    |> assign(:tracking_flash_for, lead.id)
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

  defp voice_place_call(socket) do
    attrs = %{
      "name" => socket.assigns.voice_name,
      "phone" => socket.assigns.voice_phone,
      "context" => socket.assigns.voice_context
    }

    case Leads.create_lead(socket.assigns.department, attrs) do
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
  def render(%{department: nil} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={:calls}>
      <div class="mx-auto max-w-lg px-4 py-24 text-center">
        <.icon name="hero-user-circle" class="mx-auto size-10 text-base-content/25" />
        <h1 class="mt-4 text-lg font-semibold text-base-content">No department assigned</h1>
        <p class="mt-1.5 text-sm text-base-content/60">
          Your account isn't in a department yet — ask an admin to assign you to one.
        </p>
      </div>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={:calls}>
      <div class="mx-auto max-w-5xl px-4 py-10 sm:px-6 lg:px-8">
        <header class="mb-8">
          <h1 class="text-2xl font-semibold tracking-tight text-base-content">
            {@department.name}
          </h1>
          <p class="mt-1.5 max-w-2xl text-sm text-base-content/60">
            Add a lead and CALL-E calls them immediately to follow up — no more losing deals to
            slow follow-up. Each call's outcome and summary show up here the moment it ends.
          </p>
        </header>

        <div class="mb-8 grid grid-cols-2 gap-3 sm:grid-cols-5">
          <div class="rounded-xl border border-base-300 bg-base-100 px-4 py-3">
            <div class="text-xs font-medium text-base-content/50">Calls today</div>
            <div class="mt-1 text-xl font-semibold text-primary">{@calls_today}</div>
          </div>
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
                placeholder="e.g. This is our first call to this client - introduce ourselves and ask about their current supplier. Or: let them know invoice #4521 is overdue and ask when they can settle it."
                rows="2"
              />
              <p class="mt-1.5 text-xs text-base-content/40">
                Opens with: <span class="font-medium">"{Lead.opening_line(@department.name)}"</span>
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
                      <div class="text-xs text-base-content/40">{lead.source}</div>
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
