defmodule CallAssistantWeb.Admin.UsersLive do
  @moduledoc """
  Every user account, and the only way new ones get created (there's no
  public self-registration - see the router's `:require_admin`
  live_session).
  """

  use CallAssistantWeb, :live_view

  alias CallAssistant.Accounts
  alias CallAssistant.Accounts.User
  alias CallAssistant.Departments

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Users")
     |> assign(:user_form, to_form(Accounts.change_user_by_admin(%User{})))
     |> assign(:departments, Departments.list_departments())
     |> assign(:users, Accounts.list_users())}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
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
         |> assign(:users, Accounts.list_users())
         |> push_patch(to: ~p"/admin/users")}

      {:error, changeset} ->
        {:noreply, assign(socket, :user_form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={:users}>
      <div class="mx-auto max-w-4xl px-4 py-10 sm:px-6 lg:px-8">
        <header class="mb-8 flex flex-wrap items-start justify-between gap-4">
          <div>
            <h1 class="text-2xl font-semibold tracking-tight text-base-content">Users</h1>
            <p class="mt-1.5 text-sm text-base-content/60">
              Every account with access, and which department (if any) they're in.
            </p>
          </div>
          <.link patch={~p"/admin/users/new"} class="btn btn-primary btn-sm">
            <.icon name="hero-plus-micro" class="size-4" /> New user
          </.link>
        </header>

        <div
          :if={@live_action == :new}
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
              <.link patch={~p"/admin/users"} class="btn btn-ghost h-10">Cancel</.link>
            </div>
          </.form>
        </div>

        <div class="overflow-hidden rounded-xl border border-base-300 bg-base-100 shadow-sm">
          <table class="min-w-full divide-y divide-base-300 text-sm">
            <thead class="bg-base-200/60 text-left text-xs font-medium tracking-wide text-base-content/50 uppercase">
              <tr>
                <th class="px-4 py-3">Email</th>
                <th class="px-4 py-3">Role</th>
                <th class="px-4 py-3">Department</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-base-300">
              <tr :for={user <- @users} class="transition-colors hover:bg-base-200/40">
                <td class="px-4 py-3 font-medium text-base-content">{user.email}</td>
                <td class="px-4 py-3 text-base-content/70 capitalize">{user.role}</td>
                <td class="px-4 py-3 text-base-content/70">
                  {if user.department, do: user.department.name, else: "—"}
                </td>
              </tr>
              <tr :if={@users == []}>
                <td colspan="3" class="px-4 py-16 text-center text-sm text-base-content/50">
                  No users yet.
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
