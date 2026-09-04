defmodule CallAssistant.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  The `CallAssistant.Accounts.Scope` allows public interfaces to receive
  information about the caller, such as if the call is initiated from an
  end-user, and if so, which user. Additionally, such a scope can carry fields
  such as "super user" or other privileges for use in authorization checks,
  or to ensure specific code paths can only be accessed for a given scope.

  It is useful for logging as well as for scoping pubsub subscriptions and
  broadcasts when a caller subscribes to an interface or performs a particular
  action.

  Feel free to extend the fields on this struct to fit the needs of
  growing application requirements.
  """

  alias CallAssistant.Accounts.User

  defstruct user: nil

  @doc """
  Creates a scope for the given user.

  Returns nil if no user is given.
  """
  def for_user(%User{} = user) do
    %__MODULE__{user: user}
  end

  def for_user(nil), do: nil

  @doc "True if this scope's user is an admin (sees every department)."
  def admin?(%__MODULE__{user: %User{role: "admin"}}), do: true
  def admin?(_scope), do: false

  @doc "The department id a member scope is confined to, or nil for admins."
  def department_id(%__MODULE__{user: %User{department_id: department_id}}), do: department_id

  @doc """
  Whether this scope can access the given page (a key from
  `CallAssistant.Accounts.Permissions.pages/0`, e.g. `"reports"`) - always
  true for an admin (this only ever restricts a member's own portal, never
  admin access), otherwise whether that key is in the user's own
  `permissions` list, set by an admin from `CallAssistantWeb.Admin.UsersLive`.
  Calls itself isn't a permission key at all - every member account always
  has it, so there's nothing to check for it.
  """
  def can_access?(%__MODULE__{user: %User{role: "admin"}}, _page), do: true

  def can_access?(%__MODULE__{user: %User{permissions: permissions}}, page),
    do: page in permissions

  def can_access?(_scope, _page), do: false
end
