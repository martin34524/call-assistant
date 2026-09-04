defmodule CallAssistantWeb.UserLive.InviteTest do
  use CallAssistantWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import CallAssistant.AccountsFixtures

  alias CallAssistant.Accounts
  alias CallAssistant.Accounts.UserToken
  alias CallAssistant.Repo

  setup do
    %{user: member_user_fixture(%{password: nil})}
  end

  test "renders the set-password form for a valid invite token", %{conn: conn, user: user} do
    {encoded_token, _hashed_token} = generate_user_invite_token(user)

    {:ok, _lv, html} = live(conn, ~p"/users/invite/#{encoded_token}")

    assert html =~ "Welcome, #{user.email}"
    assert html =~ "Set password and log in"
  end

  test "redirects with a flash for an invalid token", %{conn: conn} do
    {:ok, _lv, html} =
      live(conn, ~p"/users/invite/not-a-real-token")
      |> follow_redirect(conn, ~p"/users/log-in")

    assert html =~ "invalid or has expired"
  end

  test "redirects with a flash for an expired token", %{conn: conn, user: user} do
    {encoded_token, _hashed_token} = generate_user_invite_token(user)
    {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

    {:ok, _lv, html} =
      live(conn, ~p"/users/invite/#{encoded_token}")
      |> follow_redirect(conn, ~p"/users/log-in")

    assert html =~ "invalid or has expired"
  end

  test "setting a valid password logs the user in and burns the invite token", %{
    conn: conn,
    user: user
  } do
    {encoded_token, _hashed_token} = generate_user_invite_token(user)
    {:ok, lv, _html} = live(conn, ~p"/users/invite/#{encoded_token}")

    form =
      form(lv, "#invite_form",
        user: %{
          email: user.email,
          password: valid_user_password(),
          password_confirmation: valid_user_password()
        }
      )

    render_submit(form)
    conn = follow_trigger_action(form, conn)

    assert redirected_to(conn) == ~p"/dashboard"
    assert get_session(conn, :user_token)

    updated = Accounts.get_user!(user.id)
    assert updated.hashed_password
    refute Repo.get_by(UserToken, user_id: user.id, context: "invite")
  end

  test "a mismatched confirmation shows a validation error and doesn't consume the token", %{
    conn: conn,
    user: user
  } do
    {encoded_token, _hashed_token} = generate_user_invite_token(user)
    {:ok, lv, _html} = live(conn, ~p"/users/invite/#{encoded_token}")

    html =
      lv
      |> form("#invite_form",
        user: %{password: valid_user_password(), password_confirmation: "does-not-match"}
      )
      |> render_submit()

    assert html =~ "does not match password"
    assert Accounts.get_user_by_invite_token(encoded_token)
  end
end
