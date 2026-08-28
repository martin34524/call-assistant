defmodule CallAssistant.Repo.Migrations.AddEscalationToLeads do
  use Ecto.Migration

  def change do
    alter table(:leads) do
      add :escalation_status, :string
      add :escalation_reason, :text
      add :suggested_follow_up_goal, :text
      add :follow_up_of_id, references(:leads, on_delete: :nilify_all)
    end

    create index(:leads, [:escalation_status])
    create index(:leads, [:follow_up_of_id])
  end
end
