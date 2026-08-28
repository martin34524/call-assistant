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
end
