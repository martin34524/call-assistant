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

  def create_department(attrs) do
    %Department{}
    |> Department.changeset(attrs)
    |> Repo.insert()
  end

  def change_department(%Department{} = department, attrs \\ %{}) do
    Department.changeset(department, attrs)
  end
end
