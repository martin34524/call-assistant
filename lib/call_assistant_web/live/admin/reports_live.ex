defmodule CallAssistantWeb.Admin.ReportsLive do
  @moduledoc "Call outcomes broken down by department, across the whole org."

  use CallAssistantWeb, :live_view

  alias CallAssistant.Departments
  alias CallAssistant.Leads

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    departments = Departments.list_departments()
    by_department = Leads.status_breakdown_by_department()

    rows = Enum.map(departments, &row(&1, Map.get(by_department, &1.id, %{})))
    totals = rows |> Enum.map(& &1.breakdown) |> merge_breakdowns()

    {:ok,
     socket
     |> assign(:page_title, "Reports")
     |> assign(:rows, rows)
     |> assign(:overall, row(nil, totals))
     |> assign(:task_completed_total, Leads.count_task_completed(scope))}
  end

  defp row(department, breakdown) do
    total = Enum.sum(Map.values(breakdown))

    %{
      department: department,
      breakdown: breakdown,
      total: total,
      completed: Map.get(breakdown, "completed", 0),
      no_answer: Map.get(breakdown, "no_answer", 0),
      declined: Map.get(breakdown, "declined", 0),
      failed: Map.get(breakdown, "failed", 0)
    }
  end

  defp merge_breakdowns(breakdowns) do
    Enum.reduce(breakdowns, %{}, fn breakdown, acc ->
      Map.merge(acc, breakdown, fn _status, a, b -> a + b end)
    end)
  end

  defp completion_rate(_task_completed, 0), do: nil
  defp completion_rate(task_completed, completed), do: round(task_completed / completed * 100)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={:reports}>
      <div class="mx-auto max-w-4xl px-4 py-10 sm:px-6 lg:px-8">
        <header class="mb-8">
          <h1 class="text-2xl font-semibold tracking-tight text-base-content">Reports</h1>
          <p class="mt-1.5 text-sm text-base-content/60">Call outcomes by department.</p>
        </header>

        <div class="mb-8 grid grid-cols-2 gap-3 sm:grid-cols-3">
          <div class="rounded-xl border border-base-300 bg-base-100 px-4 py-3">
            <div class="text-xs font-medium text-base-content/50">Total leads</div>
            <div class="mt-1 text-xl font-semibold text-base-content">{@overall.total}</div>
          </div>
          <div class="rounded-xl border border-base-300 bg-base-100 px-4 py-3">
            <div class="text-xs font-medium text-base-content/50">Completed</div>
            <div class="mt-1 text-xl font-semibold text-success">{@overall.completed}</div>
          </div>
          <div class="rounded-xl border border-base-300 bg-base-100 px-4 py-3">
            <div class="text-xs font-medium text-base-content/50">Goal achieved rate</div>
            <div class="mt-1 text-xl font-semibold text-primary">
              <% rate = completion_rate(@task_completed_total, @overall.completed) %>
              {if rate, do: "#{rate}%", else: "—"}
            </div>
          </div>
        </div>

        <div class="overflow-hidden rounded-xl border border-base-300 bg-base-100 shadow-sm">
          <table class="min-w-full divide-y divide-base-300 text-sm">
            <thead class="bg-base-200/60 text-left text-xs font-medium tracking-wide text-base-content/50 uppercase">
              <tr>
                <th class="px-4 py-3">Department</th>
                <th class="px-4 py-3">Total</th>
                <th class="px-4 py-3">Completed</th>
                <th class="px-4 py-3">No answer</th>
                <th class="px-4 py-3">Declined</th>
                <th class="px-4 py-3">Failed</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-base-300">
              <tr :for={r <- @rows} class="transition-colors hover:bg-base-200/40">
                <td class="px-4 py-3 font-medium text-base-content">{r.department.name}</td>
                <td class="px-4 py-3 text-base-content/70">{r.total}</td>
                <td class="px-4 py-3 text-success">{r.completed}</td>
                <td class="px-4 py-3 text-base-content/70">{r.no_answer}</td>
                <td class="px-4 py-3 text-base-content/70">{r.declined}</td>
                <td class="px-4 py-3 text-error">{r.failed}</td>
              </tr>
              <tr :if={@rows == []}>
                <td colspan="6" class="px-4 py-16 text-center text-sm text-base-content/50">
                  No departments yet.
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
