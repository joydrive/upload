defmodule Upload.Blob do
  @moduledoc """
  An `Ecto.Schema` that represents an uploaded file in the database.

  The checksum field is a MD5 hash of the blob.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Upload.Stat

  @type key :: binary()
  @type id :: binary()

  @type t :: %__MODULE__{
          id: id(),
          key: key(),
          filename: binary(),
          content_type: binary() | nil,
          byte_size: integer(),
          checksum: binary(),
          metadata: map(),
          path: binary() | nil,
          variant: binary() | nil,
          variants: [Upload.Blob.t()] | Ecto.Association.NotLoaded.t(),
          original_blob_id: id() | nil,
          original_blob: Upload.Blob.t() | Ecto.Association.NotLoaded.t() | nil
        }

  @fields ~w(key filename content_type byte_size checksum path metadata variant original_blob_id)a
  @required_fields @fields -- ~w(path variant original_blob_id)a

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "blobs" do
    field :key, :string
    field :filename, Upload.EncryptedBinary
    field :content_type, :string
    field :byte_size, :integer
    field :checksum, :string
    field :metadata, :map, default: %{}
    field :path, :string, virtual: true

    field :variant, :string

    has_many :variants, Upload.Blob,
      foreign_key: :original_blob_id,
      references: :id

    belongs_to :original_blob, Upload.Blob, type: :binary_id

    timestamps(updated_at: false)
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(blob, attrs \\ %{}) when is_map(attrs) do
    blob
    |> cast(attrs, @fields)
    |> generate_id()
    |> validate_required(@required_fields)
    |> validate_format(:key, ~r/^[^.]*$/)
    |> add_extension_from_mime()
    |> foreign_key_constraint(:original_blob_id)
    |> validate_original_blob_id_is_not_variant()
    |> check_constraint(:variant, name: :variant_and_original_blob_id_are_only_nullable_together)
    |> maybe_upload()
    |> maybe_delete()
  end

  defp generate_id(changeset) do
    case get_field(changeset, :id) do
      nil -> put_change(changeset, :id, Ecto.UUID.generate())
      _ -> changeset
    end
  end

  defp add_extension_from_mime(changeset) when changeset.valid? do
    mime = get_field(changeset, :content_type)
    extension = MIME.extensions(mime) |> List.first()

    if extension do
      update_change(changeset, :key, fn key ->
        key <> "." <> extension
      end)
    else
      add_error(changeset, :key, "Could not set extension from MIME type: '#{mime}'")
    end
  end

  defp add_extension_from_mime(changeset), do: changeset

  @doc false
  def change_blob(%Stat{} = stat, key) do
    changeset(
      %__MODULE__{},
      Map.from_struct(stat) |> Map.put(:key, key)
    )
  end

  defp maybe_upload(changeset) do
    prepare_changes(changeset, fn changeset ->
      if changeset.action == :insert do
        %{path: path, key: key} = changeset.changes

        :ok = Upload.Storage.upload(path, key)
      end

      changeset
    end)
  end

  defp maybe_delete(changeset) do
    prepare_changes(changeset, fn changeset ->
      if changeset.action == :delete do
        {:ok, _} =
          Ecto.Multi.new()
          |> Upload.Multi.purge(:blob, changeset.data)
          |> Upload.Config.repo().transaction()
      end

      changeset
    end)
  end

  defp validate_original_blob_id_is_not_variant(changeset) do
    repo = Upload.Config.repo()

    case get_change(changeset, :original_blob_id) do
      nil ->
        changeset

      original_blob_id ->
        if repo.get(__MODULE__, original_blob_id).variant do
          add_error(
            changeset,
            :original_blob_id,
            "Can not set original_blob_id to a variant blob."
          )
        else
          changeset
        end
    end
  end
end
