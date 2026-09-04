# Speed-to-Lead

[![CI](https://github.com/martin34524/call-assistant/actions/workflows/ci.yml/badge.svg)](https://github.com/martin34524/call-assistant/actions/workflows/ci.yml)

A Phoenix LiveView app that turns a missed call or a fresh lead into an outbound
phone call within seconds, using [CALL-E](https://github.com/CALLE-AI/call-e-integrations)
to actually place and run the call, and an LLM (Claude or Gemini) to read the
finished conversation and decide what happens next.

The problem it solves: the business value of a lead drops fast the longer it
sits unanswered. Speed-to-Lead removes the delay — call it, qualify it, and if
the conversation surfaces something that needs a human or a different
department, route it there automatically.

## What it does

- **Places a real qualification call** for any new lead via CALL-E
  (`plan_call` → `run_call` → `get_call_run`), with a free-text "what's this
  call about" field instead of a fixed sales script.
- **Tracks the call live** — status, CALL-E's own progress messages, and the
  final transcript/summary/outcome, all pushed to the browser over
  `Phoenix.PubSub` as the call progresses.
- **Scopes everything by department.** Each department only ever sees its own
  leads; an admin role sees and can act on all of them. There's no public
  self-registration — every account is created directly by an admin.
- **Classifies every completed call** with an LLM to decide whether it
  surfaced something that needs attention beyond a routine close-out — and if
  so, *which* department actually needs to follow up (not always the one the
  call happened under: a call to the general line that turns out to be a
  Finance request gets routed to Finance, not left as a generic escalation).
- **Can follow up on its own.** When the classifier is confident enough, the
  app schedules the follow-up call itself a few minutes out — always linked
  back to the original call it followed up on, and always visible (with what
  it's going to say) and cancellable before it happens, never a silent
  action. A config flag is a kill switch for this behavior.
- **Calls can be scheduled for later**, not just placed immediately — by a
  person (an optional "Schedule for" field right on the call form) or by the
  AI's own auto-follow-up above. A lightweight poller
  (`CallAssistant.Leads.Scheduler`) places each one the moment it comes due;
  a scheduled call shows its content and time plainly, and can be cancelled
  right up until then.
- **Surfaces what needs a human** via a sidebar badge and a dedicated
  Escalations page, where an admin reviews the classifier's suggested
  department and follow-up goal (both editable) before placing the call.
- **Places calls hands-free by voice.** Click the mic, say "Call Jane" - it
  matches her against past leads to reuse a phone number on file (or asks
  for one), asks what the call's about, reads back what it understood, and
  waits for a spoken "yes" or a click before actually dialing. Built on the
  browser's free, built-in Web Speech API - no new API key or cost.
- **Has a public landing page** (`/`) describing what the app actually does,
  separate from the authenticated app (which lives at `/dashboard` for a
  member, `/admin` for an admin) - a logged-in visitor hitting `/` is sent
  straight to their real home instead of seeing the marketing page.

### An important honesty note

CALL-E has no live call-transfer or hangup API — only `plan_call`, `run_call`,
and `get_call_run`. So "routing to another department" and "ending a call"
are both handled the only way that's actually possible against CALL-E's real
contract:

- **Routing** is always a *new* follow-up call placed after the original one
  finishes, never a live transfer mid-call.
- **"Cancel"** stops the app from tracking/displaying a call as active; it
  cannot terminate a call that's already running on CALL-E's side.

## Tech stack

- Elixir / [Phoenix 1.8](https://phoenix.hexdocs.pm/) / Phoenix LiveView 1.2
- Ecto + PostgreSQL, Bandit as the HTTP adapter
- Tailwind v4 + daisyUI for styling (light/dark theme aware)
- [CALL-E](https://github.com/CALLE-AI/call-e-integrations) for placing and
  running phone calls
- Claude (`claude-opus-5`) or Gemini (`gemini-3.6-flash`) for call
  classification — raw HTTP via `Req`, no SDK dependency either way

## Architecture

**Behaviour-based adapters**, swapped entirely by config, used identically
for both external integrations:

| | Mock (default) | Live |
|---|---|---|
| `CallAssistant.CallE` | simulated call outcomes, no network | real CALL-E calls, real money |
| `CallAssistant.Claude` | marker-based deterministic outcomes | real Claude *or* Gemini API call |

Nothing talks to a real phone or spends real money until you explicitly
configure it — see [Configuration](#configuration).

**Background orchestration.** Placing a call and classifying a finished one
both run as supervised, unlinked `Task`s under `CallAssistant.TaskSupervisor`,
so multiple calls run concurrently and one failure can't take the app down:

- `CallAssistant.Leads.Qualifier` drives a lead through CALL-E's
  plan → run → poll-until-done flow, writing status updates as it goes.
- `CallAssistant.Leads.Escalation` picks up every call that reaches
  `"completed"`, asks the configured classifier whether it needs escalation
  and to which department, and either flags it for review or places the
  follow-up call itself.

**Department scoping.** `CallAssistant.Leads.list_leads/1` and `get_lead!/2`
take a `%CallAssistant.Accounts.Scope{}` and filter by department for anyone
who isn't an admin — this is the actual access boundary, not just a router
guard. An admin has its own real "Admin" department (seeded by migration) so
placing a call never requires picking a department first.

## Getting started

```bash
mix setup          # deps.get, ecto.create, ecto.migrate, assets.setup/build
mix call_assistant.create_admin you@example.com "a-strong-password"
mix phx.server      # or: iex -S mix phx.server
```

Then visit [`localhost:4000`](http://localhost:4000) - you'll land on the
public marketing page; log in from there with the admin account you just
created. Everything else — departments, further users, placing calls —
happens from the UI after that; there's no public sign-up.

Run the test suite (uses only the Mock adapters, no network calls, no real
API keys required):

```bash
mix precommit   # compile --warnings-as-errors, deps.unlock --unused, format, test
```

GitHub Actions runs the compile-warnings, formatting, and test checks on every
push and PR to `main` (`.github/workflows/ci.yml`), against a real Postgres
service container.

## Configuration

Copy `.env.example` to `.env`, fill in what you have, then
`source .env` before starting the server. Every integration below stays on
its Mock adapter — no real calls, no API spend — until its keys are set.

```bash
# CALL-E: places real phone calls. Leave blank to keep using the Mock adapter.
export CALLE_API_BASE_URL=
export CALLE_API_KEY=

# Call classifier (escalation detection + follow-up drafting). Leave both
# blank to keep using the deterministic Mock classifier. Anthropic is used
# if both are set.
export ANTHROPIC_API_KEY=
export GEMINI_API_KEY=
```

Other useful settings (`config/config.exs`):

- `config :call_assistant, :organization_name` — the name CALL-E opens every
  call with (default `"MacDevs"`), e.g. *"Hi, this is MacDevs Finance Office
  calling."*
- `config :call_assistant, :auto_follow_up_enabled` — kill switch for letting
  the app place a follow-up call on its own without a human's input first
  (default `true`).
- `config :call_assistant, :auto_follow_up_delay_minutes` — how far out the
  AI schedules its own follow-up calls (default `5`).
- `config :call_assistant, :scheduler_poll_interval_ms` — how often
  `CallAssistant.Leads.Scheduler` checks for scheduled calls that have come
  due (default `30_000`).

## Project layout

```
lib/call_assistant/
  leads.ex                  # the department-scoped context: reads/writes, PubSub broadcasts
  leads/lead.ex              # the Lead schema - status machine, escalation fields
  leads/qualifier.ex          # drives a lead through CALL-E's call flow
  leads/escalation.ex         # post-call classification -> pending review or auto follow-up
  leads/scheduler.ex          # polls for scheduled calls that have come due and places them
  call_e.ex, call_e/{mock,cli,live}.ex   # CALL-E adapter behaviour + implementations
  claude.ex, claude/{mock,live,gemini,prompt}.ex  # classifier adapter behaviour + implementations
  departments.ex              # department CRUD, the access-boundary entity
  accounts.ex                 # phx.gen.auth-based accounts, extended with role/department
  voice_command.ex            # pure "call <name>" transcript parsing for voice commands

lib/call_assistant_web/
  live/marketing_live.ex      # the public "/" landing page - redirects an authenticated visitor away
  live/                       # member-facing LiveViews (dashboard at /dashboard, call logs, reports)
  live/admin/                 # admin-only LiveViews (dashboard, calls, users, reports, escalations)
  components/layouts.ex       # the role-based sidebar (always-dark) + top bar, incl. escalations badge
  components/voice_command_components.ex  # the voice-command mic panel + its colocated JS hook
  router.ex                   # :require_authenticated_user vs :require_admin live_sessions
```

## Roles

- **Member** — sees and places calls only for their own department; a Calls
  tab always (it's the whole point of a member account, so it's never
  restrictable), plus whichever other pages an admin has granted them via a
  page-picker checklist on the admin's Users page (`permissions` array on
  the user, checked against `CallAssistant.Accounts.Permissions`'s registry
  of restrictable pages — Reports is the only one that exists today, but
  adding another is a one-line registry change, not a schema change).
- **Admin** — sees every department's calls, manages departments and which
  user emails are authorized under each (including each member's page
  access), places calls without needing to pick a department, and
  reviews/acts on escalations. The very first admin is created via
  `mix call_assistant.create_admin EMAIL PASSWORD` (the only place a
  password is ever set directly); every further account (admin or member)
  is created from the admin's Users page, which doesn't take a password at
  all — the new user gets an invite email with a link to set their own.
  There's still no public sign-up: an admin always creates the account
  first.
