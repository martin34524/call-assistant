defmodule CallAssistant.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `CallAssistant.Accounts` context.
  """

  import Ecto.Query

  alias CallAssistant.Accounts
  alias CallAssistant.Accounts.Scope
  alias CallAssistant.Departments

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email()
    })
  end

  def unconfirmed_user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user()

    user
  end

  def user_fixture(attrs \\ %{}) do
    user = unconfirmed_user_fixture(attrs)

    token =
      extract_user_token(fn url ->
        Accounts.deliver_login_instructions(user, url)
      end)

    {:ok, {user, _expired_tokens}} =
      Accounts.login_user_by_magic_link(token)

    user
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def set_password(user) do
    {:ok, {user, _expired_tokens}} =
      Accounts.update_user_password(user, %{password: valid_user_password()})

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    CallAssistant.Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def generate_user_magic_link_token(user) do
    {encoded_token, user_token} = Accounts.UserToken.build_email_token(user, "login")
    CallAssistant.Repo.insert!(user_token)
    {encoded_token, user_token.token}
  end

  @doc "A department, for tests that need the access-boundary entity itself."
  def department_fixture(attrs \\ %{}) do
    {:ok, department} =
      attrs
      |> Enum.into(%{name: "Dept #{System.unique_integer([:positive])}"})
      |> Departments.create_department()

    department
  end

  @doc "An admin user (no department, sees every department) with a known password."
  def admin_user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{email: unique_user_email(), role: "admin", password: valid_user_password()})
      |> Accounts.create_user_by_admin()

    user
  end

  @doc "A member user in a department (created for them unless given) with a known password."
  def member_user_fixture(attrs \\ %{}) do
    {department, attrs} = Map.pop(attrs, :department)
    department = department || department_fixture()

    {:ok, user} =
      attrs
      |> Enum.into(%{
        email: unique_user_email(),
        role: "member",
        department_id: department.id,
        password: valid_user_password()
      })
      |> Accounts.create_user_by_admin()

    user
  end

  def admin_scope_fixture(attrs \\ %{}), do: Scope.for_user(admin_user_fixture(attrs))
  def member_scope_fixture(attrs \\ %{}), do: Scope.for_user(member_user_fixture(attrs))

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    CallAssistant.Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end
end
