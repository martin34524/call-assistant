defmodule CallAssistant.Repo.Migrations.AddContextToLeads do
  use Ecto.Migration

  def change do
    alter table(:leads) do
      add :context, :text
    end
  end
end
