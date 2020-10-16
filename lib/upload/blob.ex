defmodule Upload.Blob do
  @moduledoc """
  An `Ecto.Schema` that represents an uploaded file in the database.
  """

  use Ecto.Schema

  alias Ecto.Changeset
  alias Upload.Utils

  @type key :: binary()
  @type id :: integer() | binary()

  @type t :: %__MODULE__{
          id: id(),
          key: key(),
          filename: binary(),
          content_type: binary(),
          byte_size: integer(),
          checksum: binary(),
          metadata: map(),
          path: binary() | nil
        }

  @key_length 28
  @alphabet '0123456789abcdefghijklmnopqrstuvwxyz'

  @fields ~w(key filename content_type byte_size checksum)a
  @required_fields ~w(key filename byte_size checksum)a

  @file_fields ~w(path filename content_type)a
  @required_file_fields ~w(path filename)a

  schema Utils.table_name() do
    field :key, :string
    field :filename, :string
    field :content_type, :string
    field :byte_size, :integer
    field :checksum, :string
    field :metadata, :map
    field :path, :string, virtual: true
    timestamps(updated_at: false)
  end

  @spec sign_id(id()) :: binary()
  def sign_id(id), do: Utils.sign(id, :blob)

  @spec verify_id(binary()) :: {:ok, id()} | :error
  def verify_id(signed_id), do: Utils.verify(signed_id, :blob)

  @spec generate_key() :: binary()
  def generate_key do
    @key_length
    |> :crypto.strong_rand_bytes()
    |> :binary.bin_to_list()
    |> Enum.map_join(&base36(rem(&1, 64)))
  end

  @spec from_plug(%{__struct__: Plug.Upload}) :: Changeset.t()
  def from_plug(%{__struct__: Plug.Upload} = upload) do
    from_file(Map.from_struct(upload))
  end

  @spec from_path(Path.t()) :: Changeset.t()
  def from_path(path) do
    from_file(%{
      key: generate_key(),
      path: path,
      filename: Path.basename(path),
      content_type: MIME.from_path(path)
    })
  end

  @spec changeset(t(), map()) :: Changeset.t()
  def changeset(%__MODULE__{} = upload, attrs \\ %{}) do
    upload
    |> Changeset.cast(attrs, @fields)
    |> Changeset.validate_required(@required_fields)
  end

  defp from_file(attrs) do
    %__MODULE__{}
    |> Changeset.cast(attrs, @file_fields)
    |> Changeset.validate_required(@required_file_fields)
    |> Changeset.put_change(:key, generate_key())
    |> Changeset.prepare_changes(&put_file_info/1)
  end

  defp put_file_info(changeset) do
    path = Changeset.fetch_change!(changeset, :path)
    content_type = Changeset.get_change(changeset, :content_type)

    with {:ok, %{size: byte_size}} <- File.stat(path),
         {:ok, checksum} <- FileStore.Stat.checksum_file(path),
         {:ok, metadata} <- Utils.analyze(path, content_type) do
      changeset
      |> Changeset.put_change(:byte_size, byte_size)
      |> Changeset.put_change(:checksum, checksum)
      |> Changeset.put_change(:metadata, metadata)
    else
      {:error, reason} ->
        Changeset.add_error(changeset, :path, "is invalid", reason: reason)
    end
  end

  for {digit, index} <- Enum.with_index(@alphabet) do
    defp base36(unquote(index)), do: <<unquote(digit)>>
  end

  defp base36(_), do: base36(:random.uniform(36) - 1)
end
