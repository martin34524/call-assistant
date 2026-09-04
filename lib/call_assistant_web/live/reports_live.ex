defmodule CallAssistantWeb.ReportsLive do
  @moduledoc "A department's own call outcomes at a glance."

  use CallAssistantWeb, :live_view

  alias CallAssistant.Accounts.Scope
  alias CallAssistant.Departments
  alias CallAssistant.Leads

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    cond do
      Scope.admin?(scope) ->
        {:ok, redirect(socket, to: ~p"/admin/reports")}

      not Scope.can_view_reports?(scope) ->
        {:ok,
         socket
         |> put_flash(:error, "You don't have access to that page.")
         |> redirect(to: ~p"/dashboard")}

      is_nil(Scope.department_id(scope)) ->
        {:ok, assign(socket, page_title: "Reports", department: nil)}

      true ->
        breakdown = Leads.status_breakdown(scope)
        completed = Map.get(breakdown, "completed", 0)
        task_completed = Leads.count_task_completed(scope)

        {:ok,
         socket
         |> assign(:page_title, "Reports")
         |> assign(:department, Departments.get_department!(Scope.department_id(scope)))
         |> assign(:breakdown, breakdown)
         |> assign(:total, Enum.sum(Map.values(breakdown)))
         |> assign(:completion_rate, completion_rate(task_completed, completed))}
    end
  end

  defp completion_rate(_task_completed, 0), do: nil
  defp completion_rate(task_completed, completed), do: round(task_completed / completed * 100)

  @impl true
  def render(%{department: nil} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={:reports}>
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
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={:reports}>
      <div class="mx-auto max-w-4xl px-4 py-10 sm:px-6 lg:px-8">
        <header class="mb-8">
          <h1 class="text-2xl font-semibold tracking-tight text-base-content">Reports</h1>
          <p class="mt-1.5 text-sm text-base-content/60">{@department.name}'s call outcomes.</p>
        </header>

        <div class="grid grid-cols-2 gap-3 sm:grid-cols-3">
          <div class="rounded-xl border border-base-300 bg-base-100 px-4 py-3">
            <div class="text-xs font-medium text-base-content/50">Total leads</div>
            <div class="mt-1 text-xl font-semibold text-base-content">{@total}</div>
          </div>
          <div class="rounded-xl border border-base-300 bg-base-100 px-4 py-3">
            <div class="text-xs font-medium text-base-content/50">Completed</div>
            <div class="mt-1 text-xl font-semibold text-success">
              {Map.get(@breakdown, "completed", 0)}
            </div>
          </div>
          <div class="rounded-xl border border-base-300 bg-base-100 px-4 py-3">
            <div class="text-xs font-medium text-base-content/50">Goal achieved rate</div>
            <div class="mt-1 text-xl font-semibold text-primary">
              {if @completion_rate, do: "#{@completion_rate}%", else: "—"}
            </div>
          </div>
          <div class="rounded-xl border border-base-300 bg-base-100 px-4 py-3">
            <div class="text-xs font-medium text-base-content/50">No answer</div>
            <div class="mt-1 text-xl font-semibold text-base-content/70">
              {Map.get(@breakdown, "no_answer", 0)}
            </div>
          </div>
          <div class="rounded-xl border border-base-300 bg-base-100 px-4 py-3">
            <div class="text-xs font-medium text-base-content/50">Declined</div>
            <div class="mt-1 text-xl font-semibold text-base-content/70">
              {Map.get(@breakdown, "declined", 0)}
            </div>
          </div>
          <div class="rounded-xl border border-base-300 bg-base-100 px-4 py-3">
            <div class="text-xs font-medium text-base-content/50">Failed</div>
            <div class="mt-1 text-xl font-semibold text-error">
              {Map.get(@breakdown, "failed", 0)}
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
