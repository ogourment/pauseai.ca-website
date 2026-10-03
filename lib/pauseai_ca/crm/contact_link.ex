defmodule PauseAiCa.CRM.ContactLink do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "crm_contact_links" do
    field :contact_id, :binary_id
    field :person_id, :binary_id
    timestamps(type: :utc_datetime_usec)
  end
end
