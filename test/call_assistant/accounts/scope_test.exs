defmodule CallAssistant.Accounts.ScopeTest do
  use CallAssistant.DataCase, async: true

  import CallAssistant.AccountsFixtures

  alias CallAssistant.Accounts.Scope

  describe "can_access?/2" do
    test "always true for an admin, regardless of any department's permissions" do
      admin = admin_user_fixture()
      assert Scope.can_access?(Scope.for_user(admin), "reports")
    end

    test "reflects whether the page key is in the member's department's permissions" do
      allowed_department = department_fixture(%{permissions: ["reports"]})
      restricted_department = department_fixture(%{permissions: []})

      allowed = member_user_fixture(%{department: allowed_department})
      restricted = member_user_fixture(%{department: restricted_department})

      assert Scope.can_access?(Scope.for_user(allowed), "reports")
      refute Scope.can_access?(Scope.for_user(restricted), "reports")
    end

    test "is shared by every member of the same department" do
      department = department_fixture(%{permissions: []})
      member_a = member_user_fixture(%{department: department})
      member_b = member_user_fixture(%{department: department})

      refute Scope.can_access?(Scope.for_user(member_a), "reports")
      refute Scope.can_access?(Scope.for_user(member_b), "reports")

      {:ok, _updated} = CallAssistant.Departments.toggle_permission(department, "reports")

      # Reload each member to pick up the department's new permissions,
      # same as a real member's own next request would.
      member_a = CallAssistant.Repo.preload(member_a, :department, force: true)
      member_b = CallAssistant.Repo.preload(member_b, :department, force: true)

      assert Scope.can_access?(Scope.for_user(member_a), "reports")
      assert Scope.can_access?(Scope.for_user(member_b), "reports")
    end

    test "defaults to true for a department created without specifying permissions" do
      member = member_user_fixture()
      assert Scope.can_access?(Scope.for_user(member), "reports")
    end

    test "false for a nil scope" do
      refute Scope.can_access?(nil, "reports")
    end
  end
end
