defmodule CallAssistant.Repo.Migrations.CreateLeads do
  use Ecto.Migration

  def change do
    create table(:leads) do
      add :name, :string, null: false
      add :phone, :string, null: false
      add :source, :string, null: false, default: "manual"
      add :status, :string, null: false, default: "new"

      add :goal, :text

      add :plan_id, :string
      add :confirm_token, :string
      add :call_run_id, :string

      add :interested, :boolean
      add :budget, :string
      add :timeline, :string
      add :decision_maker, :boolean
      add :callback_requested, :boolean
      add :notes, :text
      add :transcript, :text
      add :error, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:leads, [:status])
    create index(:leads, [:inserted_at])
  end
end
