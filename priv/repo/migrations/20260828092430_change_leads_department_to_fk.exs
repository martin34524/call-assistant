defmodule CallAssistant.Repo.Migrations.ChangeLeadsDepartmentToFk do
  use Ecto.Migration

  # Replaces the free-text `department` label with a real FK to
  # `departments`, now that departments are first-class records used for
  # access control. No existing lead data needs preserving (dev/demo data
  # only, cleared repeatedly through development).
  def change do
    alter table(:leads) do
      remove :department, :string
      add :department_id, references(:departments, on_delete: :restrict), null: false
    end

    create index(:leads, [:department_id])
  end
end
