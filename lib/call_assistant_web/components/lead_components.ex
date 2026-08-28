defmodule CallAssistantWeb.LeadComponents do
  @moduledoc """
  Shared display components for lead/call status, used by both the
  dashboard list (LeadsLive) and the per-lead call-logs page (LeadLive).
  """

  use Phoenix.Component

  @in_flight_statuses ~w(planning needs_clarification ready_to_run in_progress)

  def in_flight_statuses, do: @in_flight_statuses

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
