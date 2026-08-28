defmodule CallAssistantWeb.Admin.DashboardLive do
  @moduledoc """
  Admin overview: every department, its member count and call activity,
  plus the only way departments and user accounts get created (there's
  no public self-registration - see the router's `:require_admin`
  live_session).
  """

  use CallAssistantWeb, :live_view

  alias CallAssistant.Accounts
  alias CallAssistant.Accounts.User
  alias CallAssistant.Departments
  alias CallAssistant.Departments.Department
  alias CallAssistant.Leads

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Admin")
     |> assign(:department_form, to_form(Departments.change_department(%Department{})))
     |> assign(:user_form, to_form(Accounts.change_user_by_admin(%User{})))
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

  def handle_event("validate_user", %{"user" => params}, socket) do
    form =
      %User{}
      |> Accounts.change_user_by_admin(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :user_form, form)}
  end

  def handle_event("create_user", %{"user" => params}, socket) do
    case Accounts.create_user_by_admin(params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Created #{user.email}.")
         |> assign(:user_form, to_form(Accounts.change_user_by_admin(%User{})))
         |> load_departments()
         |> push_patch(to: ~p"/admin")}

      {:error, changeset} ->
        {:noreply, assign(socket, :user_form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-4xl px-4 py-10 sm:px-6 lg:px-8">
        <header class="mb-8 flex flex-wrap items-start justify-between gap-4">
          <div>
            <h1 class="text-2xl font-semibold tracking-tight text-base-content">Admin</h1>
            <p class="mt-1.5 text-sm text-base-content/60">
              Every department's calls, member counts, and today's activity.
            </p>
          </div>
          <div class="flex gap-2">
            <.link patch={~p"/admin/departments/new"} class="btn btn-soft btn-sm">
              <.icon name="hero-plus-micro" class="size-4" /> New department
            </.link>
            <.link patch={~p"/admin/users/new"} class="btn btn-primary btn-sm">
              <.icon name="hero-plus-micro" class="size-4" /> New user
            </.link>
          </div>
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

        <div
          :if={@live_action == :new_user}
          class="mb-6 rounded-xl border border-base-300 bg-base-100 p-5"
        >
          <h2 class="mb-3 text-sm font-semibold text-base-content">New user</h2>
          <.form
            for={@user_form}
            id="new-user-form"
            phx-change="validate_user"
            phx-submit="create_user"
            class="space-y-4"
          >
            <div class="flex flex-wrap items-end gap-3">
              <div class="min-w-[14rem] flex-1">
                <.input
                  field={@user_form[:email]}
                  type="email"
                  label="Email"
                  placeholder="finance@macdevs.com"
                />
              </div>
              <div class="min-w-[10rem] flex-1">
                <.input
                  field={@user_form[:password]}
                  type="password"
                  label="Initial password"
                  placeholder="At least 12 characters"
                />
              </div>
              <div class="min-w-[8rem]">
                <.input
                  field={@user_form[:role]}
                  type="select"
                  label="Role"
                  options={[{"Member", "member"}, {"Admin", "admin"}]}
                />
              </div>
              <div :if={@user_form[:role].value != "admin"} class="min-w-[10rem] flex-1">
                <.input
                  field={@user_form[:department_id]}
                  type="select"
                  label="Department"
                  prompt="Choose a department"
                  options={Enum.map(@departments, &{&1.name, &1.id})}
                />
              </div>
            </div>
            <div class="flex gap-2">
              <.button class="h-10">Create</.button>
              <.link patch={~p"/admin"} class="btn btn-ghost h-10">Cancel</.link>
            </div>
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
