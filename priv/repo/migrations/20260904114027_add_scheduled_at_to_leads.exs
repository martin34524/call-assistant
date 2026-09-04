defmodule CallAssistant.Repo.Migrations.AddScheduledAtToLeads do
  use Ecto.Migration

  def change do
    alter table(:leads) do
      add :scheduled_at, :utc_datetime_usec
    end

    create index(:leads, [:status, :scheduled_at])
  end
end
