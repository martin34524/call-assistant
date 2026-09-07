defmodule CallAssistant.Repo.Migrations.AddLanguageToLeads do
  use Ecto.Migration

  def change do
    alter table(:leads) do
      add :language, :string, default: "English", null: false
    end
  end
end
