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
      total_counts: Leads.count_leads_by_department(),
      pending_escalations: Leads.count_pending_escalations()
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
      <div class="mx-auto max-w-5xl px-4 py-10 sm:px-6 lg:px-8">
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

        <div class="mb-8 grid grid-cols-2 gap-3 sm:grid-cols-4">
          <div class="rounded-xl border border-base-300 bg-base-100 px-4 py-3">
            <div class="text-xs font-medium text-base-content/50">Departments</div>
            <div class="mt-1 text-xl font-semibold text-base-content">{length(@departments)}</div>
          </div>
          <div class="rounded-xl border border-base-300 bg-base-100 px-4 py-3">
            <div class="text-xs font-medium text-base-content/50">Calls today</div>
            <div class="mt-1 text-xl font-semibold text-primary">
              {sum_values(@today_counts)}
            </div>
          </div>
          <div class="rounded-xl border border-base-300 bg-base-100 px-4 py-3">
            <div class="text-xs font-medium text-base-content/50">Total leads</div>
            <div class="mt-1 text-xl font-semibold text-base-content">
              {sum_values(@total_counts)}
            </div>
          </div>
          <div class="rounded-xl border border-base-300 bg-base-100 px-4 py-3">
            <div class="text-xs font-medium text-base-content/50">Pending escalations</div>
            <div class="mt-1 text-xl font-semibold text-warning">
              {@pending_escalations}
            </div>
          </div>
        </div>

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

        <h2 class="mb-3 text-sm font-semibold text-base-content">Departments</h2>
        <div class="mb-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <div
            :for={department <- @departments}
            class="rounded-xl border border-base-300 bg-base-100 p-5 shadow-sm"
          >
            <div class="mb-3 flex items-start justify-between">
              <h3 class="font-semibold text-base-content">{department.name}</h3>
              <span class="text-xs text-base-content/50">
                {Map.get(@member_counts, department.id, 0)} members
              </span>
            </div>
            <div class="flex items-center gap-4 text-sm">
              <div>
                <div class="font-semibold text-primary">
                  {Map.get(@today_counts, department.id, 0)}
                </div>
                <div class="text-xs text-base-content/50">calls today</div>
              </div>
              <div>
                <div class="font-semibold text-base-content">
                  {Map.get(@total_counts, department.id, 0)}
                </div>
                <div class="text-xs text-base-content/50">calls total</div>
              </div>
            </div>
            <.link
              navigate={~p"/admin/departments/#{department.id}"}
              class="mt-4 inline-flex items-center gap-1 text-xs font-medium text-primary hover:underline"
            >
              View calls <.icon name="hero-arrow-right-micro" class="size-3.5" />
            </.link>
          </div>
          <div
            :if={@departments == []}
            class="col-span-full rounded-xl border border-base-300 bg-base-100 p-8 text-center text-sm text-base-content/50"
          >
            No departments yet — create one above.
          </div>
        </div>

        <h2 class="mb-3 text-sm font-semibold text-base-content">Integrations</h2>
        <div class="divide-y divide-base-300 rounded-xl border border-base-300 bg-base-100">
          <.integration_row name="CALL-E (call placing)" adapter={CallAssistant.CallE.client()} />
          <.integration_row name="Call classifier" adapter={CallAssistant.Claude.client()} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :name, :string, required: true
  attr :adapter, :atom, required: true

  defp integration_row(assigns) do
    {label, real?} = adapter_label(assigns.adapter)
    assigns = assign(assigns, label: label, real?: real?)

    ~H"""
    <div class="flex items-center justify-between px-4 py-3 text-sm">
      <div>
        <div class="font-medium text-base-content">{@name}</div>
        <div class="text-xs text-base-content/50">{inspect(@adapter)}</div>
      </div>
      <span class={[
        "rounded-full px-2.5 py-1 text-xs font-medium",
        if(@real?, do: "bg-success/10 text-success", else: "bg-base-200 text-base-content/60")
      ]}>
        {@label}
      </span>
    </div>
    """
  end

  # {display label, "genuinely does the real thing" flag} - CALL-E's Cli
  # adapter places real calls just as much as Live does (verified against
  # CALL-E's actual API, see CallAssistant.CallE.Cli's own moduledoc), so
  # only Mock counts as not-real here, not "not Live specifically."
  defp adapter_label(CallAssistant.CallE.Mock), do: {"Mock", false}
  defp adapter_label(CallAssistant.CallE.Cli), do: {"Live (CLI)", true}
  defp adapter_label(CallAssistant.CallE.Live), do: {"Live (API)", true}
  defp adapter_label(CallAssistant.Claude.Mock), do: {"Mock", false}
  defp adapter_label(CallAssistant.Claude.Live), do: {"Live (Claude)", true}
  defp adapter_label(CallAssistant.Claude.Gemini), do: {"Live (Gemini)", true}
  defp adapter_label(other), do: {inspect(other), false}

  defp sum_values(map), do: map |> Map.values() |> Enum.sum()
end
