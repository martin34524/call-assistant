defmodule CallAssistant.Repo.Migrations.AddCallUncertainToLeads do
  use Ecto.Migration

  def change do
    alter table(:leads) do
      add :call_uncertain, :boolean, default: false, null: false
      add :recovery_id, :string
    end
  end
end
