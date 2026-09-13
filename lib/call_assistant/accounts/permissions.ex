defmodule CallAssistant.Accounts.Permissions do
  @moduledoc """
  The restrictable pages within a member's own portal - what an admin
  picks from on `CallAssistantWeb.Admin.UsersLive`'s page-picker, and what
  `CallAssistant.Accounts.Scope.can_access?/2` checks a user's own
  `permissions` list against.

  Calls is never in this list - it's the one page every member account
  always has, since it's the entire point of the account. This is the
  single place a new restrictable member page gets registered: add it to
  `@pages` and to `@view_map` (so `key_for_view/2` can resolve it), and
  it's enforced automatically by `CallAssistantWeb.UserAuth`'s
  `on_mount(:ensure_page_access, ...)` hook (see the `:app` live_session
  in the router) - no per-LiveView guard code needed, not a schema change.
  """

  @pages [
    %{key: "reports", label: "Reports"}
  ]

  # Maps a LiveView module + live_action to the page key that protects it,
  # so the router-level on_mount hook can look up "does this scope have
  # access to whatever's mounting" generically instead of every page
  # writing its own check (mirrors vumbuzi_erp's Pages.key_for_view/2).
  # A view/action pair with no entry here is simply unprotected.
  @view_map %{
    {CallAssistantWeb.ReportsLive, :index} => "reports"
  }

  def pages, do: @pages
  def page_keys, do: Enum.map(@pages, & &1.key)

  @doc "Resolves the page key (if any) that protects a mounting LiveView, or nil when unprotected."
  def key_for_view(view, live_action), do: Map.get(@view_map, {view, live_action})
end
