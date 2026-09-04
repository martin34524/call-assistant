defmodule CallAssistant.Repo.Migrations.AddCanViewReportsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :can_view_reports, :boolean, default: true, null: false
    end
  end
end
