defmodule Upload.Migrations do
  @moduledoc """
  Performs database migrations required for the Upload library.

  ```elxiir
  defmodule MyApp.Repo.Migrations.AddUpload do
    use Ecto.Migration

    def up, do: Upload.Migrations.up()

    def down, do: Upload.Migrations.down()
  end
  ```
  """
  use Ecto.Migration

  def up do
    create table(:blobs, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:key, :string, null: false)
      add(:filename, :binary, null: false)
      add(:content_type, :string, null: false)
      add(:metadata, :jsonb, default: "{}", null: false)
      add(:byte_size, :integer, null: false)
      add(:checksum, :string, null: false)

      add(:variant, :string)
      add(:original_blob_id, references(:blobs, type: :binary_id), type: :binary_id)

      timestamps(updated_at: false)
    end

    create(
      constraint(:blobs, "variant_and_original_blob_id_are_only_nullable_together",
        check:
          "(variant is not null and original_blob_id is not null) or (variant is null and original_blob_id is null)",
        comment: "The variant field must be set if the original blob id is set and vice-versa"
      )
    )

    unique_index(:blobs, :key)

    unique_index(:blobs, [:variant, :original_blob_id],
      comment: "There can only be one variant per blob with the same variant name."
    )
  end

  def down do
    drop table(:blobs)

    drop unique_index(:blobs, :key)

    drop unique_index(:blobs, [:variant, :original_blob_id],
      comment: "There can only be one variant per blob with the same variant name."
    )
  end
end
