defmodule CallAssistantWeb.LeadComponents do
  @moduledoc """
  Shared display components for lead/call status, used by both the
  dashboard list (LeadsLive) and the per-lead call-logs page (LeadLive).
  """

  use Phoenix.Component

  import CallAssistantWeb.CoreComponents

  @in_flight_statuses ~w(planning needs_clarification ready_to_run in_progress)
  @cancellable_statuses @in_flight_statuses ++ ["scheduled"]

  def in_flight_statuses, do: @in_flight_statuses

  @doc """
  True while a lead's call is either still active or hasn't been placed
  yet but is scheduled to be - the two situations where offering a Cancel
  button makes sense.
  """
  def cancellable?(lead), do: lead.status in @cancellable_statuses

  @doc """
  True once a lead's status has settled (a real CALL-E terminal status, or
  our own "cancelled") - used by pages to know when to auto-dismiss the
  "Calling ... now" flash they showed when the call started.
  """
  def settled?(status),
    do: status == "cancelled" or status in CallAssistant.CallE.terminal_statuses()

  @doc """
  A "Cancel" action for an in-flight lead. Renders nothing once the lead
  is no longer cancellable. Expects the parent LiveView to handle a
  `"cancel_call"` event with `%{"id" => lead_id}` (see
  `CallAssistant.Leads.cancel/2`).
  """
  attr :lead, :any, required: true

  def cancel_button(assigns) do
    confirm =
      if assigns.lead.status == "scheduled" do
        "Cancel this scheduled call? It hasn't been placed yet - this cancels it for good."
      else
        "Stop tracking this call? CALL-E has no way for us to hang up - it may still finish the call on its own. This only stops it showing as active here."
      end

    assigns = assign(assigns, :confirm, confirm)

    ~H"""
    <button
      :if={cancellable?(@lead)}
      type="button"
      phx-click="cancel_call"
      phx-value-id={@lead.id}
      data-confirm={@confirm}
      class="text-xs font-medium text-error hover:underline"
    >
      Cancel
    </button>
    """
  end

  @doc """
  A "Redial" action for a lead whose call has already settled (see
  `settled?/1` - the same statuses `cancel_button/1` is never shown for,
  so the two buttons never both appear on the same lead). Opens the
  confirmation popup (`redial_modal/1`) rather than calling right away -
  expects the parent LiveView to handle a `"start_redial"` event with
  `%{"id" => lead_id}`.
  """
  attr :lead, :any, required: true

  def redial_button(assigns) do
    ~H"""
    <button
      :if={settled?(@lead.status)}
      type="button"
      phx-click="start_redial"
      phx-value-id={@lead.id}
      class="text-xs font-medium text-primary hover:underline"
    >
      Redial
    </button>
    """
  end

  @doc """
  The redial confirmation popup: shows the lead's previous call context,
  editable, before actually placing the new call - opened by
  `redial_button/1`. Renders nothing when `redial` is `nil` (closed).
  Expects the parent LiveView to hold a `:redial` assign shaped as
  `%{lead: %CallAssistant.Leads.Lead{}, form: form}` (see `start_redial`/
  `cancel_redial`/`confirm_redial` in e.g. `CallAssistantWeb.LeadsLive`),
  where `form` wraps a single `"context"` field pre-filled from the
  original lead, and to handle `"cancel_redial"` and `"confirm_redial"`
  (the latter with `%{"redial" => %{"context" => context}}`, passed to
  `CallAssistant.Leads.redial/3`).
  """
  attr :redial, :any, default: nil

  def redial_modal(assigns) do
    ~H"""
    <div
      :if={@redial}
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 px-4"
    >
      <div class="w-full max-w-md rounded-xl bg-base-100 p-5 shadow-xl">
        <h2 class="text-sm font-semibold text-base-content">Redial {@redial.lead.name}?</h2>
        <p class="mt-1 text-xs text-base-content/50">
          Use the same context as last time, or edit it before calling again.
        </p>
        <div
          :if={@redial.lead.call_uncertain}
          class="mt-3 rounded-lg border border-warning/30 bg-warning/10 p-3 text-xs text-warning"
        >
          <p class="flex items-center gap-1.5 font-medium">
            <.icon name="hero-exclamation-triangle-micro" class="size-4 shrink-0" />
            This call may have already connected before we lost track of it.
          </p>
          <p class="mt-1 text-warning/80">
            Check its real status before calling again to avoid contacting them twice.
          </p>
          <p :if={@redial.lead.recovery_id} class="mt-1 font-mono text-warning/70">
            recovery id: {@redial.lead.recovery_id}
          </p>
        </div>
        <.form for={@redial.form} id="redial-form" phx-submit="confirm_redial" class="mt-3 space-y-3">
          <.input
            field={@redial.form[:context]}
            type="textarea"
            label="What's this call about?"
            rows="3"
          />
          <div class="flex justify-end gap-2">
            <button type="button" phx-click="cancel_redial" class="btn btn-ghost btn-sm">
              Cancel
            </button>
            <.button class="btn-sm">Call now</.button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  attr :status, :string, required: true

  attr :call_uncertain, :boolean,
    default: false,
    doc:
      "true when a \"failed\" status might mean CALL-E actually started the call before we lost track of it - see Lead's call_uncertain field"

  def status_badge(assigns) do
    {label, classes} =
      case assigns.status do
        "new" ->
          {"New", "bg-base-300 text-base-content/70"}

        "scheduled" ->
          {"Scheduled", "bg-secondary/15 text-secondary"}

        "planning" ->
          {"Planning call", "bg-warning/15 text-warning"}

        "needs_clarification" ->
          {"Needs more info", "bg-warning/15 text-warning"}

        "ready_to_run" ->
          {"Dialing", "bg-info/15 text-info"}

        "in_progress" ->
          {"Call in progress", "bg-info/15 text-info"}

        "completed" ->
          {"Completed", "bg-success/15 text-success"}

        "declined" ->
          {"Declined", "bg-base-300 text-base-content/60"}

        "no_answer" ->
          {"No answer", "bg-base-300 text-base-content/60"}

        "failed" when assigns.call_uncertain ->
          {"Failed - may have connected", "bg-warning/15 text-warning"}

        "failed" ->
          {"Failed", "bg-error/15 text-error"}

        "cancelled" ->
          {"Cancelled", "bg-base-300 text-base-content/60"}

        other ->
          {other, "bg-base-300 text-base-content/70"}
      end

    assigns =
      assign(assigns,
        label: label,
        classes: classes,
        pulsing?: assigns.status in @in_flight_statuses
      )

    ~H"""
    <span class={"inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-medium #{@classes}"}>
      <span :if={@pulsing?} class="relative flex size-1.5">
        <span class="absolute inline-flex h-full w-full animate-ping rounded-full bg-current opacity-75" />
        <span class="relative inline-flex size-1.5 rounded-full bg-current" />
      </span>
      {@label}
    </span>
    """
  end

  @doc "Formats a scheduled_at for display, in the server's own time - see the Lead schema's note on datetime-local inputs carrying no timezone."
  def format_scheduled_at(nil), do: nil

  def format_scheduled_at(%DateTime{} = scheduled_at) do
    Calendar.strftime(scheduled_at, "%b %d, %Y at %H:%M")
  end

  @doc """
  A call's parsed transcript rendered as chat bubbles - shared between the
  per-lead call-logs page (`CallAssistantWeb.LeadLive`) and the "live call"
  panel on a member's dashboard (`CallAssistantWeb.LeadsLive`), which shows
  the same thing for whichever call is currently in-flight.
  """
  attr :turns, :list, required: true

  def transcript_bubbles(assigns) do
    ~H"""
    <div class="space-y-3">
      <.bubble :for={turn <- @turns} turn={turn} />
    </div>
    """
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
end
