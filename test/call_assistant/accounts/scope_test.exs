defmodule CallAssistant.Accounts.ScopeTest do
  use CallAssistant.DataCase, async: true

  import CallAssistant.AccountsFixtures

  alias CallAssistant.Accounts.Scope

  describe "can_view_reports?/1" do
    test "always true for an admin, regardless of the field" do
      admin = admin_user_fixture()
      assert Scope.can_view_reports?(Scope.for_user(admin))
    end

    test "reflects the member's own can_view_reports field" do
      allowed = member_user_fixture(%{can_view_reports: true})
      restricted = member_user_fixture(%{can_view_reports: false})

      assert Scope.can_view_reports?(Scope.for_user(allowed))
      refute Scope.can_view_reports?(Scope.for_user(restricted))
    end

    test "defaults to true for a member created without specifying it" do
      member = member_user_fixture()
      assert Scope.can_view_reports?(Scope.for_user(member))
    end

    test "false for a nil scope" do
      refute Scope.can_view_reports?(nil)
    end
  end
end
