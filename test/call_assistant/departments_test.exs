defmodule CallAssistant.DepartmentsTest do
  use CallAssistant.DataCase

  alias CallAssistant.Departments

  test "create_department/1 requires a name" do
    assert {:error, changeset} = Departments.create_department(%{})
    assert %{name: ["can't be blank"]} = errors_on(changeset)
  end

  test "create_department/1 enforces unique names" do
    assert {:ok, _} = Departments.create_department(%{name: "Finance Office"})
    assert {:error, changeset} = Departments.create_department(%{name: "Finance Office"})
    assert %{name: ["has already been taken"]} = errors_on(changeset)
  end

  test "list_departments/0 orders by name" do
    Departments.create_department(%{name: "Store Office"})
    Departments.create_department(%{name: "Accounting"})

    # The seeded "Admin" department (see admin_department/0) is always
    # present too - just assert our two sort correctly relative to it,
    # not the exact full list.
    names = Enum.map(Departments.list_departments(), & &1.name)

    assert Enum.find_index(names, &(&1 == "Accounting")) <
             Enum.find_index(names, &(&1 == "Admin"))

    assert Enum.find_index(names, &(&1 == "Admin")) <
             Enum.find_index(names, &(&1 == "Store Office"))
  end

  test "admin_department/0 returns the seeded admin department" do
    department = Departments.admin_department()
    assert department.name == "Admin"
    assert department.is_admin_department == true
  end
end
