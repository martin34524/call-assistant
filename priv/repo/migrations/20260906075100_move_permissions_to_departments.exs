defmodule CallAssistant.Repo.Migrations.MovePermissionsToDepartments do
  use Ecto.Migration

  def up do
    alter table(:departments) do
      add :permissions, {:array, :string}, default: [], null: false
    end

    execute "UPDATE departments SET permissions = ARRAY['reports']"

    alter table(:users) do
      remove :permissions
    end
  end

  def down do
    alter table(:users) do
      add :permissions, {:array, :string}, default: [], null: false
    end

    execute "UPDATE users SET permissions = ARRAY['reports']"

    alter table(:departments) do
      remove :permissions
    end
  end
end
