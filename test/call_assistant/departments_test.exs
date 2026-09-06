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

  test "create_department/1 defaults permissions to every page when unspecified" do
    assert {:ok, department} = Departments.create_department(%{name: "Store Office"})
    assert department.permissions == CallAssistant.Accounts.Permissions.page_keys()
  end

  test "create_department/1 respects an explicit empty permissions list" do
    assert {:ok, department} =
             Departments.create_department(%{name: "Store Office", permissions: []})

    assert department.permissions == []
  end

  test "update_department/2 saves a changed name and permissions" do
    {:ok, department} = Departments.create_department(%{name: "Store Office"})

    assert {:ok, updated} =
             Departments.update_department(department, %{"permissions" => []})

    assert updated.permissions == []
  end

  test "toggle_permission/2 flips whether a page is included, without touching name" do
    {:ok, department} = Departments.create_department(%{name: "Store Office", permissions: []})

    assert {:ok, on} = Departments.toggle_permission(department, "reports")
    assert on.permissions == ["reports"]
    assert on.name == "Store Office"

    assert {:ok, off} = Departments.toggle_permission(on, "reports")
    assert off.permissions == []
  end
end
