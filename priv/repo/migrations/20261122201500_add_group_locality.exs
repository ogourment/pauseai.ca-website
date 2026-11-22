defmodule PauseAiCa.Repo.Migrations.AddGroupLocality do
  use Ecto.Migration

  def up do
    alter table(:incubator_profiles) do
      add :area_served, :string, null: false, default: "internal"
      add :office_address, :string
    end

    execute "UPDATE incubator_profiles SET area_served = 'local' WHERE published"

    execute """
    UPDATE incubator_profiles SET fsas = ARRAY[CASE lower(name_en)
      WHEN 'toronto' THEN 'M5H' WHEN 'ottawa' THEN 'K1P' ELSE 'H2W' END]::varchar[]
    WHERE published AND cardinality(fsas) = 0 AND lower(name_en) IN ('toronto','ottawa','montréal','montreal')
    """

    create constraint(:incubator_profiles, :public_profiles_are_local,
             check:
               "area_served IN ('internal','local') AND (NOT published OR area_served = 'local')"
           )
  end

  def down do
    drop constraint(:incubator_profiles, :public_profiles_are_local)

    alter table(:incubator_profiles) do
      remove :office_address
      remove :area_served
    end
  end
end
