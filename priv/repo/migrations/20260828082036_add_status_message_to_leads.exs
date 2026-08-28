defmodule CallAssistant.Repo.Migrations.AddStatusMessageToLeads do
  use Ecto.Migration

  def change do
    alter table(:leads) do
      add :status_message, :string
    end
  end
end
