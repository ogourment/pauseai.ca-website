defmodule PauseAiCa.Repo.Migrations.AddBlogArticles do
  use Ecto.Migration

  def change do
    create table(:blog_articles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :text, null: false
      add :payload, :map, null: false, default: %{}
      add :published_payload, :map
      add :published_revision, :integer
      add :published_at, :utc_datetime_usec
      add :archived_at, :utc_datetime_usec
      add :revision, :integer, null: false, default: 0
      add :updated_by, references(:users, type: :binary_id)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:blog_articles, [:slug])
    create constraint(:blog_articles, :blog_articles_revision_nonnegative, check: "revision >= 0")

    create table(:blog_article_revisions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :article_id, references(:blog_articles, type: :binary_id), null: false
      add :revision, :integer, null: false
      add :editor_id, references(:users, type: :binary_id), null: false
      add :action, :text, null: false
      add :payload, :map, null: false
      add :published_payload, :map
      add :published_revision, :integer
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:blog_article_revisions, [:article_id, :revision])

    create constraint(:blog_article_revisions, :blog_article_revisions_action,
             check:
               "action IN ('created', 'saved', 'published', 'restored', 'unpublished', 'archived')"
           )
  end
end
