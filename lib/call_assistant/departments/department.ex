defmodule CallAssistant.Departments.Department do
  use Ecto.Schema
  import Ecto.Changeset

  schema "departments" do
    field :name, :string
    # True for exactly one row (enforced by a partial unique index) - the
    # admin's own calling identity, defaulted to when an admin places a
    # call without picking a department. See Departments.admin_department/0.
    field :is_admin_department, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(department, attrs) do
    department
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, max: 100)
    |> unique_constraint(:name)
  end
end
