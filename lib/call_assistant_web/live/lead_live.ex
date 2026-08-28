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
    lead = Leads.get_lead!(scope, id)

    {:ok,
     socket
     |> assign(:page_title, "#{lead.name} - Call log")
     |> assign(:lead, lead)}
  end

  @impl true
  def handle_info({:lead_updated, updated_lead}, socket) do
    socket =
      if updated_lead.id == socket.assigns.lead.id do
        assign(socket, :lead, updated_lead)
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

  attr :turn, :map, required: true

  defp bubble(assigns) do
    ~H"""
    <div class={[
      "flex",
      @turn.speaker == :bot && "justify-start",
      @turn.speaker == :user && "justify-end"
    ]}>
      <div class={[
        "max-w-lg rounded-2xl px-4 py-2.5 text-sm",
        @turn.speaker == :bot && "bg-base-200 text-base-content",
        @turn.speaker == :user && "bg-primary text-primary-content"
      ]}>
        <div class={[
          "mb-0.5 text-[0.65rem] font-semibold tracking-wide uppercase",
          @turn.speaker == :bot && "text-base-content/50",
          @turn.speaker == :user && "text-primary-content/70"
        ]}>
          {if @turn.speaker == :bot, do: "CALL-E", else: "Them"}
          <span :if={@turn.time} class="font-normal normal-case">· {@turn.time}</span>
        </div>
        <div class="whitespace-pre-wrap">{@turn.text}</div>
      </div>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :turns, Transcript.parse(assigns.lead.transcript))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-3xl px-4 py-10 sm:px-6 lg:px-8">
        <.link
          navigate={~p"/"}
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
          </div>
        </header>

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

        <div class="rounded-xl border border-base-300 bg-base-100 p-5">
          <h2 class="mb-4 text-sm font-semibold text-base-content">Conversation</h2>

          <div :if={@turns != []} class="space-y-3">
            <.bubble :for={turn <- @turns} turn={turn} />
          </div>

          <div :if={@turns == [] and @lead.call_run_id == nil} class="py-10 text-center">
            <.icon name="hero-phone" class="mx-auto size-8 text-base-content/25" />
            <p class="mt-3 text-sm text-base-content/50">
              No call has been placed for this lead yet.
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
