defmodule CallAssistantWeb.Admin.DashboardLive do
  @moduledoc """
  Admin overview: every department, its member count and call activity,
  plus the only way departments get created (there's no public
  self-registration - see the router's `:require_admin` live_session).
  User accounts are created from `CallAssistantWeb.Admin.UsersLive`.
  """

  use CallAssistantWeb, :live_view

  alias CallAssistant.Accounts
  alias CallAssistant.Departments
  alias CallAssistant.Departments.Department
  alias CallAssistant.Leads

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Admin")
     |> assign(:department_form, to_form(Departments.change_department(%Department{})))
     |> load_departments()}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  defp load_departments(socket) do
    departments = Departments.list_departments()

    member_counts =
      Map.new(departments, &{&1.id, length(Accounts.list_users_by_department(&1.id))})

    assign(socket,
      departments: departments,
      member_counts: member_counts,
      today_counts: Leads.count_calls_today_by_department(),
      total_counts: Leads.count_leads_by_department()
    )
  end

  @impl true
  def handle_event("validate_department", %{"department" => params}, socket) do
    form =
      %Department{}
      |> Departments.change_department(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :department_form, form)}
  end

  def handle_event("create_department", %{"department" => params}, socket) do
    case Departments.create_department(params) do
      {:ok, department} ->
        {:noreply,
         socket
         |> put_flash(:info, "Created #{department.name}.")
         |> assign(:department_form, to_form(Departments.change_department(%Department{})))
         |> load_departments()
         |> push_patch(to: ~p"/admin")}

      {:error, changeset} ->
        {:noreply, assign(socket, :department_form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={:overview}>
      <div class="mx-auto max-w-4xl px-4 py-10 sm:px-6 lg:px-8">
        <header class="mb-8 flex flex-wrap items-start justify-between gap-4">
          <div>
            <h1 class="text-2xl font-semibold tracking-tight text-base-content">Overview</h1>
            <p class="mt-1.5 text-sm text-base-content/60">
              Every department's calls, member counts, and today's activity.
            </p>
          </div>
          <.link patch={~p"/admin/departments/new"} class="btn btn-primary btn-sm">
            <.icon name="hero-plus-micro" class="size-4" /> New department
          </.link>
        </header>

        <div
          :if={@live_action == :new_department}
          class="mb-6 rounded-xl border border-base-300 bg-base-100 p-5"
        >
          <h2 class="mb-3 text-sm font-semibold text-base-content">New department</h2>
          <.form
            for={@department_form}
            id="new-department-form"
            phx-change="validate_department"
            phx-submit="create_department"
            class="flex items-end gap-3"
          >
            <div class="flex-1">
              <.input field={@department_form[:name]} label="Name" placeholder="Finance Office" />
            </div>
            <.button class="h-10">Create</.button>
            <.link patch={~p"/admin"} class="btn btn-ghost h-10">Cancel</.link>
          </.form>
        </div>

        <div class="overflow-hidden rounded-xl border border-base-300 bg-base-100 shadow-sm">
          <table class="min-w-full divide-y divide-base-300 text-sm">
            <thead class="bg-base-200/60 text-left text-xs font-medium tracking-wide text-base-content/50 uppercase">
              <tr>
                <th class="px-4 py-3">Department</th>
                <th class="px-4 py-3">Members</th>
                <th class="px-4 py-3">Calls today</th>
                <th class="px-4 py-3">Calls total</th>
                <th class="px-4 py-3"></th>
              </tr>
            </thead>
            <tbody class="divide-y divide-base-300">
              <tr :for={department <- @departments} class="transition-colors hover:bg-base-200/40">
                <td class="px-4 py-3 font-medium text-base-content">{department.name}</td>
                <td class="px-4 py-3 text-base-content/70">
                  {Map.get(@member_counts, department.id, 0)}
                </td>
                <td class="px-4 py-3 font-semibold text-primary">
                  {Map.get(@today_counts, department.id, 0)}
                </td>
                <td class="px-4 py-3 text-base-content/70">
                  {Map.get(@total_counts, department.id, 0)}
                </td>
                <td class="px-4 py-3 text-right">
                  <.link
                    navigate={~p"/admin/departments/#{department.id}"}
                    class="inline-flex items-center gap-1 text-xs font-medium text-primary hover:underline"
                  >
                    View calls <.icon name="hero-arrow-right-micro" class="size-3.5" />
                  </.link>
                </td>
              </tr>
              <tr :if={@departments == []}>
                <td colspan="5" class="px-4 py-16 text-center text-sm text-base-content/50">
                  No departments yet — create one above.
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
