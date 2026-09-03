defmodule CallAssistantWeb.LeadComponents do
  @moduledoc """
  Shared display components for lead/call status, used by both the
  dashboard list (LeadsLive) and the per-lead call-logs page (LeadLive).
  """

  use Phoenix.Component

  @in_flight_statuses ~w(planning needs_clarification ready_to_run in_progress)

  def in_flight_statuses, do: @in_flight_statuses

  @doc "True while a lead's call is still active enough to offer a Cancel button for."
  def cancellable?(lead), do: lead.status in @in_flight_statuses

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
    ~H"""
    <button
      :if={cancellable?(@lead)}
      type="button"
      phx-click="cancel_call"
      phx-value-id={@lead.id}
      data-confirm="Stop tracking this call? CALL-E has no way for us to hang up - it may still finish the call on its own. This only stops it showing as active here."
      class="text-xs font-medium text-error hover:underline"
    >
      Cancel
    </button>
    """
  end

  attr :status, :string, required: true

  def status_badge(assigns) do
    {label, classes} =
      case assigns.status do
        "new" -> {"New", "bg-base-300 text-base-content/70"}
        "planning" -> {"Planning call", "bg-warning/15 text-warning"}
        "needs_clarification" -> {"Needs more info", "bg-warning/15 text-warning"}
        "ready_to_run" -> {"Dialing", "bg-info/15 text-info"}
        "in_progress" -> {"Call in progress", "bg-info/15 text-info"}
        "completed" -> {"Completed", "bg-success/15 text-success"}
        "declined" -> {"Declined", "bg-base-300 text-base-content/60"}
        "no_answer" -> {"No answer", "bg-base-300 text-base-content/60"}
        "failed" -> {"Failed", "bg-error/15 text-error"}
        "cancelled" -> {"Cancelled", "bg-base-300 text-base-content/60"}
        other -> {other, "bg-base-300 text-base-content/70"}
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
