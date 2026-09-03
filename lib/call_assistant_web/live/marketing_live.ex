defmodule CallAssistantWeb.MarketingLive do
  @moduledoc """
  The public front door at `"/"` - only ever seen by a logged-out visitor,
  since an authenticated one is redirected straight to their real home
  (`/admin` or `/dashboard`) in `mount/3` below. There's no public
  self-registration in this app (see `CallAssistant.Accounts` - every
  account is created directly by an admin), so every call-to-action here
  points at `/users/log-in`, never a signup flow that doesn't exist.
  """

  use CallAssistantWeb, :live_view

  alias CallAssistant.Accounts.Scope

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope do
      target = if Scope.admin?(scope), do: ~p"/admin", else: ~p"/dashboard"
      {:ok, redirect(socket, to: target)}
    else
      {:ok, assign(socket, :page_title, "Speed-to-Lead")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="bg-base-100">
        <header class="border-b border-base-300">
          <div class="mx-auto flex max-w-6xl items-center justify-between px-4 py-4 sm:px-6 lg:px-8">
            <a href="/" class="flex items-center gap-2.5">
              <span class="flex size-8 items-center justify-center rounded-full bg-primary text-primary-content">
                <.icon name="hero-phone-arrow-up-right-micro" class="size-4" />
              </span>
              <span class="text-sm font-semibold tracking-tight">Speed-to-Lead</span>
            </a>
            <nav class="hidden items-center gap-6 text-sm text-base-content/60 sm:flex">
              <a href="#how-it-works" class="hover:text-base-content">How it works</a>
              <a href="#use-cases" class="hover:text-base-content">Use cases</a>
              <a
                href="https://github.com/martin34524/call-assistant"
                class="hover:text-base-content"
              >
                Source
              </a>
            </nav>
            <.link navigate={~p"/users/log-in"} class="btn btn-primary btn-sm">
              Log in
            </.link>
          </div>
        </header>

        <section class="mx-auto max-w-6xl px-4 py-16 sm:px-6 lg:px-8 lg:py-24">
          <div class="grid items-center gap-12 lg:grid-cols-2">
            <div>
              <div class="mb-4 inline-flex items-center gap-1.5 rounded-full border border-base-300 px-3 py-1 text-xs font-medium tracking-wide text-base-content/60 uppercase">
                Built on CALL-E · Phoenix + LiveView
              </div>
              <h1 class="text-4xl font-bold tracking-tight text-base-content sm:text-5xl">
                Never let a lead go cold waiting on a callback.
              </h1>
              <p class="mt-5 max-w-xl text-base text-base-content/70">
                Speed-to-Lead calls a new lead within seconds of intake - CALL-E places a real
                phone call, holds the conversation, and hands back a transcript and summary.
                Every finished call gets classified automatically, and routed to the right
                department if it turns out to need one.
              </p>
              <div class="mt-8 flex flex-wrap gap-3">
                <.link navigate={~p"/users/log-in"} class="btn btn-primary">
                  <.icon name="hero-phone-arrow-up-right-micro" class="size-4" /> Log in
                </.link>
                <a
                  href="https://github.com/martin34524/call-assistant"
                  class="btn btn-outline"
                >
                  View source on GitHub
                </a>
              </div>
              <p class="mt-3 text-xs text-base-content/40">
                No public sign-up - accounts are created directly by an admin.
              </p>
            </div>

            <div class="rounded-2xl border border-base-300 bg-base-200/40 p-5 shadow-sm">
              <div class="mb-3 flex items-center justify-between">
                <div class="flex items-center gap-2">
                  <span class="flex size-8 items-center justify-center rounded-full bg-primary/10 text-xs font-semibold text-primary">
                    JD
                  </span>
                  <div>
                    <div class="text-sm font-medium text-base-content">Jordan Lee</div>
                    <div class="text-xs text-base-content/50">Example call</div>
                  </div>
                </div>
                <span class="flex items-center gap-1 text-xs font-medium text-success">
                  <span class="size-1.5 rounded-full bg-success"></span> Completed
                </span>
              </div>
              <div class="space-y-2 text-sm">
                <div class="rounded-xl bg-base-100 px-3 py-2 text-base-content/80">
                  Hi, this is calling about your recent inquiry. Do you have a minute?
                </div>
                <div class="ml-auto max-w-[85%] rounded-xl bg-primary px-3 py-2 text-primary-content">
                  Sure, go ahead.
                </div>
                <div class="rounded-xl bg-base-100 px-3 py-2 text-base-content/80">
                  Great - can I ask what budget you're working with?
                </div>
              </div>
              <div class="mt-3 rounded-xl bg-neutral px-4 py-3 font-mono text-xs text-neutral-content">
                <div>status: <span class="text-success">"completed"</span></div>
                <div>task_completed: <span class="text-warning">true</span></div>
                <div>summary: "Confirmed continued interest, requested a callback."</div>
              </div>
            </div>
          </div>
        </section>

        <section class="border-y border-base-300 bg-base-200/40 py-8">
          <div class="mx-auto max-w-6xl px-4 sm:px-6 lg:px-8">
            <p class="mb-4 text-center text-xs font-medium tracking-wide text-base-content/40 uppercase">
              Built with
            </p>
            <div class="flex flex-wrap items-center justify-center gap-x-10 gap-y-3 text-sm font-medium text-base-content/60">
              <span>Elixir &amp; Phoenix LiveView</span>
              <span>CALL-E</span>
              <span>Claude</span>
              <span>Gemini</span>
            </div>
          </div>
        </section>

        <section id="how-it-works" class="mx-auto max-w-6xl px-4 py-16 sm:px-6 lg:px-8">
          <p class="text-xs font-semibold tracking-wide text-primary uppercase">How it works</p>
          <h2 class="mt-2 text-3xl font-bold tracking-tight text-base-content">
            From a new lead to a classified outcome, automatically.
          </h2>

          <div class="mt-10 grid gap-8 sm:grid-cols-2 lg:grid-cols-4">
            <div
              :for={
                {title, description} <- [
                  {"Add a lead",
                   "A name, phone number, and free-text context - what this call is about."},
                  {"CALL-E calls immediately",
                   "No queue, no dialer - the call is placed within seconds via plan_call/run_call."},
                  {"Transcript & classification",
                   "The finished call's transcript and summary are read back, then classified automatically."},
                  {"Escalation if warranted",
                   "Flagged for review, or - when confident enough - a follow-up call is placed on its own."}
                ]
              }
              class="relative"
            >
              <div class="mb-3 flex size-9 items-center justify-center rounded-full bg-primary/10 text-sm font-semibold text-primary">
                {title |> String.first()}
              </div>
              <h3 class="font-semibold text-base-content">{title}</h3>
              <p class="mt-1.5 text-sm text-base-content/60">{description}</p>
            </div>
          </div>
        </section>

        <section id="use-cases" class="border-t border-base-300 bg-base-200/40 py-16">
          <div class="mx-auto max-w-6xl px-4 sm:px-6 lg:px-8">
            <p class="text-xs font-semibold tracking-wide text-primary uppercase">Use cases</p>
            <h2 class="mt-2 text-3xl font-bold tracking-tight text-base-content">
              One pipeline, three ways to use it.
            </h2>

            <div class="mt-10 grid gap-6 sm:grid-cols-3">
              <div
                :for={
                  {icon, title, description} <- [
                    {"hero-bolt-micro", "Speed-to-lead qualification",
                     "Call every new lead within seconds instead of hours - qualify interest, budget, and timeline while it's still fresh."},
                    {"hero-arrow-path-rounded-square-micro", "Department routing & escalation",
                     "A call classified as needing a different department's attention gets a follow-up placed there automatically."},
                    {"hero-microphone-micro", "Voice-driven calling",
                     "Say \"call Jane,\" give context out loud, confirm, and it's dialed - no form required."}
                  ]
                }
                class="rounded-xl border border-base-300 bg-base-100 p-6"
              >
                <.icon name={icon} class="size-6 text-primary" />
                <h3 class="mt-4 font-semibold text-base-content">{title}</h3>
                <p class="mt-1.5 text-sm text-base-content/60">{description}</p>
              </div>
            </div>
          </div>
        </section>

        <section class="bg-neutral py-10 text-neutral-content">
          <div class="mx-auto grid max-w-6xl grid-cols-2 gap-6 px-4 text-center sm:grid-cols-4 sm:px-6 lg:px-8">
            <div
              :for={
                text <- [
                  "Every call classified automatically",
                  "No live transfer needed - full context carries to the follow-up",
                  "Voice or form - same pipeline either way",
                  "Full transcript & summary, every time"
                ]
              }
              class="text-sm font-medium"
            >
              {text}
            </div>
          </div>
        </section>

        <section class="py-16 text-center">
          <h2 class="text-2xl font-bold tracking-tight text-base-content">
            Ready to stop losing leads to slow follow-up?
          </h2>
          <div class="mt-6">
            <.link navigate={~p"/users/log-in"} class="btn btn-primary">
              Log in
            </.link>
          </div>
        </section>

        <footer class="border-t border-base-300 py-10">
          <div class="mx-auto flex max-w-6xl flex-col items-center justify-between gap-4 px-4 text-sm text-base-content/50 sm:flex-row sm:px-6 lg:px-8">
            <div class="flex items-center gap-2">
              <span class="flex size-6 items-center justify-center rounded-full bg-primary text-primary-content">
                <.icon name="hero-phone-arrow-up-right-micro" class="size-3" />
              </span>
              <span>Speed-to-Lead - built on CALL-E</span>
            </div>
            <div class="flex gap-5">
              <a href="#how-it-works" class="hover:text-base-content">How it works</a>
              <a href="#use-cases" class="hover:text-base-content">Use cases</a>
              <a
                href="https://github.com/martin34524/call-assistant"
                class="hover:text-base-content"
              >
                GitHub
              </a>
              <.link navigate={~p"/users/log-in"} class="hover:text-base-content">Log in</.link>
            </div>
          </div>
        </footer>
      </div>
    </Layouts.app>
    """
  end
end
