defmodule CallAssistant.Repo.Migrations.MovePermissionsBackToUsers do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :permissions, {:array, :string}, default: [], null: false
    end

    execute """
    UPDATE users SET permissions = departments.permissions
    FROM departments WHERE users.department_id = departments.id
    """

    alter table(:departments) do
      remove :permissions
    end
  end

  def down do
    alter table(:departments) do
      add :permissions, {:array, :string}, default: [], null: false
    end

    execute """
    UPDATE departments SET permissions = sub.permissions
    FROM (
      SELECT DISTINCT ON (department_id) department_id, permissions
      FROM users
      WHERE department_id IS NOT NULL
      ORDER BY department_id, updated_at DESC
    ) AS sub
    WHERE departments.id = sub.department_id
    """

    alter table(:users) do
      remove :permissions
    end
  end
end
