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

    assert Enum.map(Departments.list_departments(), & &1.name) == ["Accounting", "Store Office"]
  end
end
