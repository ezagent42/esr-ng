defmodule EzagentCore.Repo.Migrations.EntityProfiles do
  @moduledoc """
  Username & Auth M1 — entity-agnostic display profiles.

  One row per Entity URI (user OR agent). `display_name` is the
  friendly name shown in the UI; `email` is user-only and the
  resolution key for magic-link login (M3). URI stays the immutable
  system primary key — this table holds the mutable attributes.
  """
  use Ecto.Migration

  def change do
    create table(:entity_profiles, primary_key: false) do
      add :entity_uri, :string, primary_key: true
      add :display_name, :string, null: false
      add :email, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:entity_profiles, [:email],
             where: "email IS NOT NULL",
             name: :entity_profiles_email_index
           )
  end
end
