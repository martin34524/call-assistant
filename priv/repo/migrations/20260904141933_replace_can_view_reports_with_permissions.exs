defmodule CallAssistant.Repo.Migrations.ReplaceCanViewReportsWithPermissions do
  use Ecto.Migration

  # Generalizes the single can_view_reports boolean into an extensible list
  # of page keys an admin can grant a member (see
  # CallAssistant.Accounts.Permissions) - "reports" is the only real page
  # today, but this scales to more without another migration each time.

  def up do
    alter table(:users) do
      add :permissions, {:array, :string}, default: [], null: false
    end

    execute "UPDATE users SET permissions = ARRAY['reports'] WHERE can_view_reports = true"

    alter table(:users) do
      remove :can_view_reports
    end
  end

  def down do
    alter table(:users) do
      add :can_view_reports, :boolean, default: true, null: false
    end

    execute "UPDATE users SET can_view_reports = ('reports' = ANY(permissions))"

    alter table(:users) do
      remove :permissions
    end
  end
end
