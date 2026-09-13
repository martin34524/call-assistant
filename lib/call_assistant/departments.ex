defmodule CallAssistant.Departments do
  @moduledoc """
  Departments are the access boundary between the "each department only
  sees its own calls" world and the admin's "see everything" world - see
  `CallAssistant.Leads` for how they're used to scope reads/writes.

  Creating/listing departments is admin-only; that's enforced by the
  router (`live_session :require_admin`), not here.
  """

  import Ecto.Query, warn: false

  alias CallAssistant.Repo
  alias CallAssistant.Departments.Department

  def list_departments do
    Repo.all(from d in Department, order_by: d.name)
  end

  def get_department!(id), do: Repo.get!(Department, id)
  def get_department(id), do: Repo.get(Department, id)

  @doc """
  Case-insensitive exact match on name, or `nil`. Used to resolve a
  classifier-suggested department name (see `CallAssistant.Leads.Escalation`)
  against a real record - a name is never trusted as an id on its own.
  """
  def get_department_by_name(name) when is_binary(name) do
    normalized = String.trim(name)

    Repo.one(
      from d in Department, where: fragment("lower(?)", d.name) == ^String.downcase(normalized)
    )
  end

  def get_department_by_name(_), do: nil

  @doc """
  The admin's own calling identity - a real department, seeded by
  migration, that an admin's calls default to when they don't pick one.
  Lets "which department is this call for" be optional for admins
  instead of a hard-required field.
  """
  def admin_department, do: Repo.get_by!(Department, is_admin_department: true)

  def create_department(attrs) do
    %Department{}
    |> Department.changeset(attrs)
    |> Repo.insert()
  end

  def change_department(%Department{} = department, attrs \\ %{}) do
    Department.changeset(department, attrs)
  end
end
