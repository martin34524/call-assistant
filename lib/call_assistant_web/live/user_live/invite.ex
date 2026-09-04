defmodule CallAssistantWeb.UserLive.Invite do
  @moduledoc """
  Where an admin-created user (see `CallAssistantWeb.Admin.UsersLive` -
  `Accounts.create_user_by_admin/1` never sets a password) lands from their
  invite email to set one for the first time. Not a login page - there's no
  session yet - the token itself is the proof of identity.
  """

  use CallAssistantWeb, :live_view

  alias CallAssistant.Accounts

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if user = Accounts.get_user_by_invite_token(token) do
      {:ok,
       socket
       |> assign(:page_title, "Set your password")
       |> assign(:token, token)
       |> assign(:user, user)
       |> assign(:form, to_form(Accounts.change_user_password(user, %{}, hash_password: false)))
       |> assign(:trigger_submit, false)}
    else
      {:ok,
       socket
       |> put_flash(
         :error,
         "This invite link is invalid or has expired - ask an admin to resend it."
       )
       |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    form =
      socket.assigns.user
      |> Accounts.change_user_password(params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("set_password", %{"user" => params}, socket) do
    case Accounts.set_password_by_invite_token(socket.assigns.token, params) do
      {:ok, {_user, _expired_tokens}} ->
        params = Map.put(params, "email", socket.assigns.user.email)
        {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, :invalid_or_expired_token} ->
        {:noreply,
         socket
         |> put_flash(:error, "This invite link is invalid or has expired.")
         |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm px-4 py-16">
        <div class="text-center">
          <.header>
            Welcome, {@user.email}
            <:subtitle>Set a password to finish setting up your account.</:subtitle>
          </.header>
        </div>

        <.form
          for={@form}
          id="invite_form"
          action={~p"/users/log-in"}
          phx-change="validate"
          phx-submit="set_password"
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name={@form[:email].name} value={@form[:email].value} />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            autocomplete="new-password"
            required
            phx-mounted={JS.focus()}
          />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label="Confirm password"
            autocomplete="new-password"
            required
          />
          <.button phx-disable-with="Setting password…" class="btn btn-primary mt-4 w-full">
            Set password and log in
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
