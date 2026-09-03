defmodule CallAssistantWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use CallAssistantWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :active_nav, :atom,
    default: nil,
    doc: "which sidebar tab to highlight (:calls, :reports, :overview, :users, ...)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="flex min-h-screen">
      <aside
        :if={@current_scope}
        class="flex w-56 shrink-0 flex-col bg-zinc-950 text-zinc-100"
      >
        <a href={home_path(@current_scope)} class="flex items-center gap-2.5 px-4 py-4">
          <span class="flex size-8 items-center justify-center rounded-full bg-primary text-primary-content">
            <.icon name="hero-phone-arrow-up-right-micro" class="size-4" />
          </span>
          <span class="text-sm font-semibold tracking-tight text-white">Speed-to-Lead</span>
        </a>

        <nav class="flex-1 space-y-1 px-3">
          <.nav_link :for={item <- nav_items(@current_scope)} item={item} active={@active_nav} />
        </nav>

        <div class="border-t border-zinc-800 px-3 py-3">
          <div class="truncate text-xs text-zinc-400">{@current_scope.user.email}</div>
          <div class="mt-2 flex items-center justify-between">
            <div class="flex gap-3 text-xs">
              <.link navigate="/users/settings" class="text-zinc-400 hover:text-white">
                Settings
              </.link>
              <.link
                href="/users/log-out"
                method="delete"
                class="text-zinc-400 hover:text-white"
              >
                Log out
              </.link>
            </div>
            <.theme_toggle />
          </div>
        </div>
      </aside>

      <div class="flex min-w-0 flex-1 flex-col">
        <div
          :if={@current_scope}
          class="flex items-center justify-end gap-4 border-b border-base-300 bg-base-100 px-6 py-3"
        >
          <.link
            :if={CallAssistant.Accounts.Scope.admin?(@current_scope)}
            navigate="/admin/escalations"
            class="relative text-base-content/60 hover:text-base-content"
            title="Escalations"
          >
            <.icon name="hero-bell-micro" class="size-5" />
            <span
              :if={escalation_badge_count()}
              class="absolute -top-0.5 -right-0.5 size-2 rounded-full bg-error"
            ></span>
          </.link>
          <.link
            navigate="/users/settings"
            class="flex size-8 items-center justify-center rounded-full bg-primary/10 text-xs font-semibold text-primary"
            title={@current_scope.user.email}
          >
            {user_initials(@current_scope)}
          </.link>
        </div>

        <main class="min-w-0 flex-1">
          {render_slot(@inner_block)}
        </main>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  defp nav_items(scope) do
    if CallAssistant.Accounts.Scope.admin?(scope) do
      [
        %{key: :overview, label: "Overview", icon: "hero-squares-2x2-micro", path: "/admin"},
        %{
          key: :calls,
          label: "Calls",
          icon: "hero-phone-arrow-up-right-micro",
          path: "/admin/calls"
        },
        %{key: :users, label: "Users", icon: "hero-users-micro", path: "/admin/users"},
        %{key: :reports, label: "Reports", icon: "hero-chart-bar-micro", path: "/admin/reports"},
        %{
          key: :escalations,
          label: "Escalations",
          icon: "hero-bell-alert-micro",
          path: "/admin/escalations",
          badge: escalation_badge_count()
        }
      ]
    else
      [
        %{
          key: :calls,
          label: "Calls",
          icon: "hero-phone-arrow-up-right-micro",
          path: "/dashboard"
        },
        %{key: :reports, label: "Reports", icon: "hero-chart-bar-micro", path: "/reports"}
      ]
    end
  end

  defp home_path(scope) do
    if CallAssistant.Accounts.Scope.admin?(scope), do: "/admin", else: "/dashboard"
  end

  defp user_initials(scope) do
    scope.user.email
    |> String.split("@")
    |> List.first()
    |> String.slice(0, 2)
    |> String.upcase()
  end

  # Cheap aggregate query, called on every sidebar render. Acceptable for
  # this app's traffic - keeps every admin page from having to remember
  # to pass the count as an assign, and it's the one number in the UI
  # that genuinely needs to be current on every navigation.
  defp escalation_badge_count do
    case CallAssistant.Leads.count_pending_escalations() do
      0 -> nil
      count -> count
    end
  end

  attr :item, :map, required: true
  attr :active, :atom, default: nil

  defp nav_link(assigns) do
    ~H"""
    <.link
      navigate={@item.path}
      class={[
        "flex items-center gap-2.5 rounded-lg px-3 py-2 text-sm font-medium transition-colors",
        if(@active == @item.key,
          do: "bg-primary text-primary-content",
          else: "text-zinc-400 hover:bg-zinc-900 hover:text-white"
        )
      ]}
    >
      <.icon name={@item.icon} class="size-4" />
      <span class="flex-1">{@item.label}</span>
      <span
        :if={Map.get(@item, :badge)}
        class="flex size-5 items-center justify-center rounded-full bg-error text-[0.65rem] font-semibold text-error-content"
      >
        {@item.badge}
      </span>
    </.link>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
