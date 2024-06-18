defmodule Upload.Test.Repo.Migrations.AddPeople do
  use Ecto.Migration

  def change do
    create table(:people) do
      add(:avatar_id, references(:blobs, on_delete: :nilify_all, type: :binary_id),
        type: :binary_id
      )
    end
  end
end
