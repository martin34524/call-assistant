defmodule CallAssistant.Repo.Migrations.AddRoleAndDepartmentToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :role, :string, null: false, default: "member"
      add :department_id, references(:departments, on_delete: :restrict)
    end

    create index(:users, [:department_id])
  end
end
