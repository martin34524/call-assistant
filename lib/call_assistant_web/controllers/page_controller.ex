defmodule CallAssistantWeb.PageController do
  use CallAssistantWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
