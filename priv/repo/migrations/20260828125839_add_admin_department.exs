defmodule CallAssistant.Repo.Migrations.AddAdminDepartment do
  use Ecto.Migration

  # Marks one department as the admin's own calling identity, so placing
  # a call as admin doesn't require picking a department first - it's
  # optional, defaulting to this one. Marked structurally (a boolean, not
  # matched by name "Admin") so a rename later doesn't break the default.
  def up do
    alter table(:departments) do
      add :is_admin_department, :boolean, null: false, default: false
    end

    create unique_index(:departments, [:is_admin_department],
             where: "is_admin_department = true",
             name: :departments_single_admin_department_index
           )

    execute("""
    INSERT INTO departments (name, is_admin_department, inserted_at, updated_at)
    VALUES ('Admin', true, NOW(), NOW())
    """)
  end

  def down do
    drop unique_index(:departments, [:is_admin_department],
           name: :departments_single_admin_department_index
         )

    alter table(:departments) do
      remove :is_admin_department
    end
  end
end
