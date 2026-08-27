defmodule CallAssistant.Leads do
  @moduledoc """
  Context for managing leads and kicking off CALL-E qualification calls.
  """

  import Ecto.Query, warn: false

  alias CallAssistant.Repo
  alias CallAssistant.Leads.{Lead, Qualifier}

  @topic "leads"

  def subscribe do
    Phoenix.PubSub.subscribe(CallAssistant.PubSub, @topic)
  end

  def list_leads do
    Repo.all(from l in Lead, order_by: [desc: l.inserted_at])
  end

  def get_lead!(id), do: Repo.get!(Lead, id)

  @doc """
  Creates a lead and immediately kicks off the CALL-E qualification call
  in the background (speed-to-lead: call within seconds of intake).
  """
  def create_lead(attrs) do
    with {:ok, lead} <-
           %Lead{}
           |> Lead.create_changeset(attrs)
           |> Repo.insert() do
      broadcast(lead)
      Qualifier.start(lead)
      {:ok, lead}
    end
  end

  def update_lead(%Lead{} = lead, attrs) do
    with {:ok, lead} <-
           lead
           |> Lead.update_changeset(attrs)
           |> Repo.update() do
      broadcast(lead)
      {:ok, lead}
    end
  end

  def change_lead(%Lead{} = lead, attrs \\ %{}) do
    Lead.create_changeset(lead, attrs)
  end

  defp broadcast(%Lead{} = lead) do
    Phoenix.PubSub.broadcast(CallAssistant.PubSub, @topic, {:lead_updated, lead})
    lead
  end
end
