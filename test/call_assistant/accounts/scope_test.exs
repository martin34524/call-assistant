defmodule CallAssistant.Accounts.ScopeTest do
  use CallAssistant.DataCase, async: true

  import CallAssistant.AccountsFixtures

  alias CallAssistant.Accounts.Scope

  describe "can_access?/2" do
    test "always true for an admin, regardless of permissions" do
      admin = admin_user_fixture()
      assert Scope.can_access?(Scope.for_user(admin), "reports")
    end

    test "reflects whether the page key is in the member's own permissions" do
      allowed = member_user_fixture(%{permissions: ["reports"]})
      restricted = member_user_fixture(%{permissions: []})

      assert Scope.can_access?(Scope.for_user(allowed), "reports")
      refute Scope.can_access?(Scope.for_user(restricted), "reports")
    end

    test "defaults to true for a member created without specifying permissions" do
      member = member_user_fixture()
      assert Scope.can_access?(Scope.for_user(member), "reports")
    end

    test "false for a nil scope" do
      refute Scope.can_access?(nil, "reports")
    end
  end
end
