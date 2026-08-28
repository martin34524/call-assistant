defmodule CallAssistant.Repo.Migrations.AddDepartmentToLeads do
  use Ecto.Migration

  def change do
    alter table(:leads) do
      add :department, :string
    end
  end
end
