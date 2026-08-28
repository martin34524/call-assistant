defmodule CallAssistant.AccountsAdminTest do
  @moduledoc """
  Tests for the admin-specific parts of Accounts (create_user_by_admin,
  list_users, delete_user) - kept separate from the generated
  accounts_test.exs so that file stays untouched.
  """

  use CallAssistant.DataCase

  import CallAssistant.AccountsFixtures

  alias CallAssistant.Accounts

  test "list_users/0 preloads department and orders by role then email" do
    department = department_fixture(%{name: "Finance Office"})
    admin = admin_user_fixture(%{email: "zz-admin@example.com"})
    member = member_user_fixture(%{email: "aa-member@example.com", department: department})

    users = Accounts.list_users()
    ids = Enum.map(users, & &1.id)

    assert admin.id in ids
    assert member.id in ids

    found_member = Enum.find(users, &(&1.id == member.id))
    assert found_member.department.name == "Finance Office"
  end

  test "delete_user/1 removes the account" do
    user = member_user_fixture()
    assert {:ok, _} = Accounts.delete_user(user)
    refute Accounts.get_user_by_email(user.email)
  end
end
