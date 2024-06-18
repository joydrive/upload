defmodule Upload do
  @moduledoc """
  An opinionated file uploader.
  """

  alias Upload.Stat
  alias Upload.Blob

  @spec stat(String.t() | Plug.Upload.t()) :: {:ok, Stat.t()} | {:error, any()}
  def stat(path) when is_binary(path) do
    Stat.stat(path)
  end

  def stat(%Plug.Upload{path: path} = upload) do
    with {:ok, stat} <- Stat.stat(path) do
      stat =
        stat
        |> Stat.put(:filename, upload.filename)
        |> Stat.put(:content_type, upload.content_type)

      {:ok, stat}
    end
  end

  def stat!(path) do
    case stat(path) do
      {:ok, stat} ->
        stat

      {:error, reason} when is_atom(reason) ->
        raise File.Error, path: path, reason: reason, action: "read file stats"

      {:error, exception} when is_struct(exception) ->
        raise exception
    end
  end

  @spec variant_exists?(Blob.t(), String.t() | atom()) :: boolean()
  def variant_exists?(%Blob{id: blob_id}, variant) do
    import Ecto.Query
    repo = Upload.Config.repo()

    Blob
    |> where([blob], blob.id == ^blob_id and blob.variant == ^to_string(variant))
    |> repo.exists?()
  end

  @doc """
  Creates and uploads a single variant of a blob.

  Calling this multiple times is not the optimal for creating multiple variants
  of a blob at once since this function would download the original blob once
  per variant. See `create_multiple_variants/3`.

  ## Example

  ```elixir
  create_variant(original_blob, "small", &transform_fn/3)
  ```
  """
  @spec create_variant(Blob.t(), String.t(), any()) :: {:ok, Blob.t()} | {:error, any()}
  def create_variant(original_blob, variant, transform) when is_function(transform, 3) do
    with {:ok, blob_path} <- create_random_file(),
         :ok <- Upload.Storage.download(original_blob.key, blob_path),
         {:ok, variant_path} <- create_random_file(),
         :ok <- apply(transform, [blob_path, variant_path, variant]),
         :ok <- cleanup(blob_path),
         {:ok, blob} <- insert_variant(original_blob, variant, variant_path),
         :ok <- cleanup(variant_path) do
      {:ok, blob}
    end
  end

  @doc """
  Creates multiple versions of a blob after downloading the source blob once.
  Useful for creating multiple versions of a photo for example.

  ## Example

  ```elixir
  create_multiple_variants(blob, ["small", "large"], &transform_fn/3)
  ```
  """
  @spec create_multiple_variants(Blob.t(), [String.t()], any()) :: any()
  def create_multiple_variants(original_blob, variants, transform)
      when is_function(transform, 3) do
    with {:ok, blob_path} <- create_random_file(),
         :ok <- Upload.Storage.download(original_blob.key, blob_path),
         {:ok, blobs} <- insert_variants(variants, original_blob, blob_path, transform),
         :ok <- cleanup(blob_path) do
      {:ok, blobs}
    end
  end

  defp insert_variants(variants, original_blob, blob_path, transform) do
    Enum.reduce_while(variants, {:ok, []}, fn variant, {:ok, blobs} ->
      with {:ok, variant_path} <- create_random_file(),
           :ok <- apply(transform, [blob_path, variant_path, variant]),
           {:ok, blob} <- insert_variant(original_blob, variant, variant_path),
           :ok <- cleanup(variant_path) do
        {:cont, {:ok, blobs ++ [blob]}}
      else
        {:error, error} ->
          {:halt, {:error, "Failed to create variant #{variant} with error #{error}"}}
      end
    end)
  end

  defp insert_variant(original_blob, variant, variant_path) do
    if original_blob.variant do
      raise "A variant of a blob can not be created for a blob that is already a variant"
    end

    repo = Upload.Config.repo()
    original_key_without_ext = Path.rootname(original_blob.key)

    params =
      variant_path
      |> Upload.stat!()
      |> Map.from_struct()
      |> Map.put(:variant, variant)
      |> Map.put(:original_blob_id, original_blob.id)
      |> Map.put(:key, original_key_without_ext <> "/variant/" <> to_string(variant))
      |> Map.put(:filename, variant_filename(original_blob, variant))

    changeset = Blob.changeset(%Blob{}, params)

    repo.insert(changeset)
  end

  defp variant_filename(original_blob, variant) do
    original_ext = Path.extname(original_blob.filename)
    without_ext = Path.rootname(original_blob.filename)

    without_ext <> "_" <> to_string(variant) <> original_ext
  end

  defp create_random_file do
    case Plug.Upload.random_file("upload") do
      {:ok, tmp} -> {:ok, tmp}
      reason -> {:error, %Upload.RandomFileError{reason: reason}}
    end
  end

  defp cleanup(path) do
    with {:error, reason} <- File.rm(path) do
      %File.Error{path: path, reason: reason, action: "remove temporary file"}
    end
  end

  # *  `:cache_control`
  # *  `:content_disposition`
  # *  `:content_encoding`
  # *  `:content_length`
  # *  `:content_type`
  # *  `:expect`
  # *  `:expires`
  # *  `:storage_class`
  # *  `:website_redirect_location`
  # *  `:encryption` (set to "AES256" for encryption at rest)
  # defp set_headers(blob) do
  # end

  # def put_acl(blob) do
  # end
end
