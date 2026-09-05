defmodule CallAssistantWeb.LeadLive do
  use CallAssistantWeb, :live_view

  alias CallAssistant.Leads
  alias CallAssistant.Leads.Transcript

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    if connected?(socket), do: Leads.subscribe(scope)

    # Raises Ecto.NoResultsError (-> 404) if this lead isn't visible to
    # the caller's scope - a member can't reach another department's
    # lead just by guessing its id.
    lead =
      scope
      |> Leads.get_lead!(id)
      |> CallAssistant.Repo.preload([:follow_up_of, :follow_ups])

    {:ok,
     socket
     |> assign(:page_title, "#{lead.name} - Call log")
     |> assign(:lead, lead)}
  end

  @impl true
  def handle_event("cancel_call", %{"id" => id}, socket) do
    Leads.cancel(socket.assigns.current_scope, id)
    {:noreply, socket}
  end

  def handle_event("redial", %{"id" => id}, socket) do
    case Leads.redial(socket.assigns.current_scope, id) do
      {:ok, lead} ->
        {:noreply,
         socket
         |> put_flash(:info, "Calling #{lead.name} now…")
         |> push_navigate(to: ~p"/leads/#{lead.id}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't redial that lead.")}
    end
  end

  @impl true
  def handle_info({:lead_updated, updated_lead}, socket) do
    socket =
      if updated_lead.id == socket.assigns.lead.id do
        lead = CallAssistant.Repo.preload(updated_lead, [:follow_up_of, :follow_ups])
        assign(socket, :lead, lead)
      else
        socket
      end

    {:noreply, socket}
  end

  defp initials(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&String.first/1)
    |> Enum.take(2)
    |> Enum.join()
    |> String.upcase()
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :turns, Transcript.parse(assigns.lead.transcript))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-3xl px-4 py-10 sm:px-6 lg:px-8">
        <.link
          navigate={~p"/dashboard"}
          class="inline-flex items-center gap-1 text-sm text-base-content/50 hover:text-base-content"
        >
          <.icon name="hero-arrow-left-micro" class="size-4" /> Back to dashboard
        </.link>

        <header class="mt-4 mb-6 flex items-start gap-4">
          <span class="flex size-12 shrink-0 items-center justify-center rounded-full bg-primary/10 text-sm font-semibold text-primary">
            {initials(@lead.name)}
          </span>
          <div class="min-w-0 flex-1">
            <h1 class="text-xl font-semibold tracking-tight text-base-content">{@lead.name}</h1>
            <p class="text-sm text-base-content/60">
              {@lead.phone}
              <span>· {@lead.department.name}</span>
              <span>· {@lead.source}</span>
            </p>
          </div>
          <div class="text-right">
            <.status_badge status={@lead.status} />
            <div :if={@lead.status_message} class="mt-1 text-xs text-base-content/40">
              {@lead.status_message}
            </div>
            <div class="mt-1 flex items-center gap-3">
              <.redial_button lead={@lead} />
              <.cancel_button lead={@lead} />
            </div>
          </div>
        </header>

        <div :if={@lead.goal} class="mb-6 rounded-xl border border-base-300 bg-base-100 p-4">
          <div
            :if={@lead.status == "scheduled"}
            class="mb-1 flex items-center gap-1.5 text-sm font-medium text-secondary"
          >
            <.icon name="hero-clock-micro" class="size-4 shrink-0" />
            Scheduled for {CallAssistantWeb.LeadComponents.format_scheduled_at(@lead.scheduled_at)}
          </div>
          <p :if={@lead.status != "scheduled"} class="mb-1 text-sm font-medium text-base-content/70">
            What we told the AI
          </p>
          <p class="text-sm text-base-content/70">
            {if @lead.status == "scheduled",
              do: "Here's what it will say when it's placed:",
              else: "The instructions given for this call:"}
          </p>
          <p class="mt-1 rounded-lg bg-base-100 p-3 text-sm whitespace-pre-wrap text-base-content/80">
            {@lead.goal}
          </p>
        </div>

        <div
          :if={@lead.summary || @lead.error}
          class="mb-6 rounded-xl border border-base-300 bg-base-100 p-4"
        >
          <div
            :if={@lead.task_completed == true}
            class="mb-1 flex items-center gap-1 text-sm font-medium text-success"
          >
            <.icon name="hero-check-circle-micro" class="size-4" /> Goal achieved
          </div>
          <div
            :if={@lead.task_completed == false}
            class="mb-1 flex items-center gap-1 text-sm font-medium text-base-content/50"
          >
            <.icon name="hero-minus-circle-micro" class="size-4" /> Goal not achieved
          </div>
          <p :if={@lead.summary} class="text-sm text-base-content/70">{@lead.summary}</p>
          <p :if={@lead.error} class="flex items-center gap-1 text-sm text-error">
            <.icon name="hero-exclamation-triangle-micro" class="size-4" /> {@lead.error}
          </p>
        </div>

        <div
          :if={@lead.follow_up_of_id || @lead.escalation_status}
          class="mb-6 rounded-xl border border-base-300 bg-base-100 p-4"
        >
          <div
            :if={@lead.follow_up_of}
            class="mb-2 flex items-center gap-1.5 text-sm text-base-content/70"
          >
            <.icon name="hero-arrow-uturn-left-micro" class="size-4 shrink-0 text-base-content/40" />
            Follow-up call for
            <.link
              navigate={~p"/leads/#{@lead.follow_up_of_id}"}
              class="font-medium text-primary hover:underline"
            >
              {@lead.follow_up_of.name}
            </.link>
          </div>

          <div :if={@lead.escalation_status in ["pending", "auto_handled"]} class="text-sm">
            <div class="mb-1 flex items-center gap-1.5 font-medium text-base-content/80">
              <.icon name="hero-bell-alert-micro" class="size-4 shrink-0 text-warning" />
              {if @lead.escalation_status == "pending",
                do: "Flagged for admin review",
                else: "Auto-followed-up"}
            </div>
            <p :if={@lead.escalation_reason} class="text-base-content/60">
              {@lead.escalation_reason}
            </p>
          </div>

          <div :if={@lead.follow_ups != []} class="mt-2 space-y-1">
            <.link
              :for={follow_up <- @lead.follow_ups}
              navigate={~p"/leads/#{follow_up.id}"}
              class="flex items-center gap-1 text-sm font-medium text-primary hover:underline"
            >
              <.icon name="hero-arrow-right-micro" class="size-3.5" /> View follow-up call
            </.link>
          </div>
        </div>

        <div class="rounded-xl border border-base-300 bg-base-100 p-5">
          <h2 class="mb-4 text-sm font-semibold text-base-content">Conversation</h2>

          <.transcript_bubbles :if={@turns != []} turns={@turns} />

          <div
            :if={@turns == [] and @lead.call_run_id == nil and @lead.status != "scheduled"}
            class="py-10 text-center"
          >
            <.icon name="hero-phone" class="mx-auto size-8 text-base-content/25" />
            <p class="mt-3 text-sm text-base-content/50">
              No call has been placed for this lead yet.
            </p>
          </div>

          <div :if={@turns == [] and @lead.status == "scheduled"} class="py-10 text-center">
            <.icon name="hero-clock" class="mx-auto size-8 text-base-content/25" />
            <p class="mt-3 text-sm text-base-content/50">
              Nothing to show yet - this call hasn't been placed. Come back after {CallAssistantWeb.LeadComponents.format_scheduled_at(
                @lead.scheduled_at
              )}.
            </p>
          </div>

          <div :if={@turns == [] and @lead.call_run_id != nil} class="py-10 text-center">
            <.icon name="hero-chat-bubble-left-right" class="mx-auto size-8 text-base-content/25" />
            <p class="mt-3 text-sm text-base-content/50">
              No transcript yet — CALL-E only returns the conversation once the call ends.
            </p>
            <p :if={@lead.status_message} class="mt-1 text-xs text-base-content/40">
              Current status: {@lead.status_message}
            </p>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
