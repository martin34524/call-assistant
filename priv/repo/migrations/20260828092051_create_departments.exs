defmodule CallAssistant.Repo.Migrations.CreateDepartments do
  use Ecto.Migration

  def change do
    create table(:departments) do
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:departments, [:name])
  end
end
