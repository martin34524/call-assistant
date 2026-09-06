defmodule CallAssistant.Departments.Department do
  use Ecto.Schema
  import Ecto.Changeset

  schema "departments" do
    field :name, :string
    # True for exactly one row (enforced by a partial unique index) - the
    # admin's own calling identity, defaulted to when an admin places a
    # call without picking a department. See Departments.admin_department/0.
    field :is_admin_department, :boolean, default: false

    # Which pages, beyond Calls (always included - it's the whole point of
    # a member account), every member of this department can access - see
    # CallAssistant.Accounts.Permissions for the registry of valid page
    # keys and CallAssistant.Accounts.Scope.can_access?/2 for the check.
    # Shared across the whole department, not per-member.
    field :permissions, {:array, :string}, default: []

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(department, attrs) do
    attrs = maybe_default_permissions(department, attrs)

    department
    |> cast(attrs, [:name, :permissions])
    |> validate_required([:name])
    |> validate_length(:name, max: 100)
    |> unique_constraint(:name)
    |> sanitize_permissions()
    |> validate_subset(:permissions, CallAssistant.Accounts.Permissions.page_keys())
  end

  # A brand-new department (never persisted, so no explicit permissions
  # given at all) defaults to every current page, matching "no
  # restriction" - only applies to a genuinely new record, never overrides
  # an existing department's own stored permissions.
  defp maybe_default_permissions(%__MODULE__{id: nil}, attrs) do
    if Map.has_key?(attrs, "permissions") or Map.has_key?(attrs, :permissions) do
      attrs
    else
      # attrs is either all string keys (a LiveView form submit) or all
      # atom keys (a test fixture calling the context directly) - Ecto's
      # cast/3 rejects a map mixing both, so match whichever this caller
      # used rather than always defaulting to a string key.
      key = if Enum.any?(Map.keys(attrs), &is_binary/1), do: "permissions", else: :permissions
      Map.put(attrs, key, CallAssistant.Accounts.Permissions.page_keys())
    end
  end

  defp maybe_default_permissions(_existing_department, attrs), do: attrs

  # The page-picker's checkboxes (if ever driven by a form rather than the
  # toggle buttons) would submit a leading hidden "" entry the same way
  # the old per-user picker did - strip that blank placeholder and any
  # duplicates before it ever reaches validate_subset/3.
  defp sanitize_permissions(changeset) do
    update_change(changeset, :permissions, fn permissions ->
      permissions |> Enum.reject(&(&1 in [nil, ""])) |> Enum.uniq()
    end)
  end
end
