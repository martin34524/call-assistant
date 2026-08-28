defmodule CallAssistant.Repo.Migrations.AddSuggestedDepartmentToLeads do
  use Ecto.Migration

  def change do
    alter table(:leads) do
      add :suggested_department_id, references(:departments, on_delete: :nilify_all)
    end

    create index(:leads, [:suggested_department_id])
  end
end
