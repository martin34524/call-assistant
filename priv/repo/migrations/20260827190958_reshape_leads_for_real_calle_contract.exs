defmodule CallAssistant.Repo.Migrations.ReshapeLeadsForRealCalleContract do
  use Ecto.Migration

  # The original schema assumed CALL-E returns custom structured fields
  # (budget, timeline, decision_maker, callback_requested, interested).
  # A real call verified it doesn't - it returns task_completed, a
  # summary, and a transcript instead. Reshape to match.
  def change do
    alter table(:leads) do
      remove :interested, :boolean
      remove :budget, :string
      remove :timeline, :string
      remove :decision_maker, :boolean
      remove :callback_requested, :boolean
      remove :notes, :text

      add :task_completed, :boolean
      add :summary, :text
    end
  end
end
