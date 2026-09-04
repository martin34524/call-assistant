defmodule CallAssistant.Accounts.Permissions do
  @moduledoc """
  The restrictable pages within a member's own portal - what an admin picks
  from on `CallAssistantWeb.Admin.UsersLive`'s page-picker, and what
  `CallAssistant.Accounts.Scope.can_access?/2` checks a user's own
  `permissions` list against.

  Calls is never in this list - it's the one page every member account
  always has, since it's the entire point of the account. This is the
  single place a new restrictable member page gets registered, so adding
  one is a one-line change here plus a guard at that page's own `mount/3`,
  not a schema change.
  """

  @pages [
    %{key: "reports", label: "Reports"}
  ]

  def pages, do: @pages
  def page_keys, do: Enum.map(@pages, & &1.key)
end
