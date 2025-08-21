defmodule Upload do
  @moduledoc """
  An opinionated file uploader.
  """

  @type variant_id :: String.t() | atom()

  alias Upload.Blob
  alias Upload.Stat

  import Ecto.Query

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

  @doc """
  Checks if a variant exists for a given `Upload.Blob` and the variant identifier.

  ## Example

      iex> Upload.variant_exists?(person.avatar, :small)
      iex> true

  """
  @spec variant_exists?(Blob.t(), variant_id()) :: boolean()
  def variant_exists?(%Blob{id: blob_id}, variant) do
    repo = Upload.Config.repo()

    Blob
    |> where([blob], blob.original_blob_id == ^blob_id and blob.variant == ^to_string(variant))
    |> repo.exists?()
  end

  @spec delete(Blob.t()) :: :ok | {:error, any()}
  def delete(blob) do
    repo = Upload.Config.repo()

    case Ecto.Multi.new()
         |> Upload.Multi.delete_blob(:remove_existing_blob, blob)
         |> repo.transaction() do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @spec delete_by_key(String.t()) :: :ok | {:error, any()}
  def delete_by_key(key) do
    repo = Upload.Config.repo()

    case repo.get_by(Upload.Blob, key: key) do
      nil ->
        :ok

      blob ->
        delete(blob)
    end
  end

  @doc """
  Returns the variant for a given `Upload.Blob` and the variant identifier or `nil` if it
  does not exist.

  ## Example

      iex> Upload.get_variant(person.avatar, :small, "image/jpeg")
      %Blob{}

  """
  @spec get_variant(Blob.t(), variant_id(), String.t()) :: nil | Blob.t()
  def get_variant(%Blob{id: blob_id}, variant, format) do
    repo = Upload.Config.repo()

    Blob
    |> where([blob], blob.original_blob_id == ^blob_id)
    |> where([blob], blob.variant == ^to_string(variant))
    |> where([blob], blob.content_type == ^to_string(format))
    |> repo.one()
  end

  @doc """
  Creates and uploads a single variant of a blob.

  Calling this multiple times is not the optimal for creating multiple variants
  of a blob at once since this function would download the original blob once
  per variant. See `create_variants/3` for a more optimal solution.

  If a transaction is needed, see `Upload.Multi.create_variant/5`.

  ## Example

      iex> create_variant(original_blob, :small, &transform_fn/3)
      {:ok, %Blob{}}
  """
  @spec create_variant(Blob.t(), String.t(), any(), keyword()) ::
          {:ok, Blob.t()} | {:error, any()}
  def create_variant(original_blob, variant, transform_fn, opts \\ [])
      when is_function(transform_fn, 3) do
    repo = Upload.Config.repo()

    Ecto.Multi.new()
    |> Upload.Multi.create_variant(original_blob, variant, transform_fn, opts)
    |> repo.transaction(Keyword.get(opts, :transaction_opts, []))
    |> case do
      {:ok, multi_result} ->
        {:ok, extract_inserts(multi_result)}

      {:error, _stage, error, _context} ->
        {:error, error}
    end
  end

  @doc """
  Creates multiple versions of a blob after downloading the source blob once.
  Useful for creating multiple versions of a photo for example.

  ## Example

      iex> create_variants(blob, [:small, :large], &transform_fn/2)
      {:ok, [%Blob{...}, %Blob{...}]}
  """
  @spec create_variants(Blob.t(), [variant_id()], any()) ::
          {:ok, [Blob.t()]} | {:error, String.t(), any()}
  def create_variants(original_blob, variants, transform_fn, opts \\ [])
      when is_function(transform_fn, 3) do
    variants = Enum.map(variants, &to_string/1)
    repo = Upload.Config.repo()

    Ecto.Multi.new()
    |> Upload.Multi.create_variants(
      original_blob,
      variants,
      transform_fn,
      opts
    )
    |> repo.transaction(Keyword.get(opts, :transaction_opts, []))
    |> case do
      {:ok, multi_result} ->
        {:ok, extract_inserts(multi_result)}

      {:error, stage, error, _} ->
        {:error, stage, error}
    end
  end

  defp extract_inserts(multi_result) do
    multi_result
    |> Enum.filter(fn {key, _} ->
      String.starts_with?(to_string(key), "download_and_insert")
    end)
    |> Enum.map(fn {_, value} -> value end)
  end

  @doc """
  Set the tags on a blob. This is useful for categorizing or managing blobs in
  storage.

  Tags can be used by permission policies or lifecycle rules when using S3 as
  the storage backend.
  """
  @spec set_tags(Blob.t(), Enumerable.t()) :: {:ok, Blob.t()} | {:error, term()}
  def set_tags(blob, tags) do
    result_id =
      "update_tags_blob_#{blob.id || raise ArgumentError, "Blob must have an ID to set tags"}"

    Enum.each(tags, fn {key, value} ->
      unless is_binary(key) and is_binary(value) do
        raise ArgumentError, "Tags must be an enumerable with string keys and values"
      end
    end)

    Ecto.Multi.new()
    |> Upload.Multi.update_tags(blob, tags)
    |> Upload.Config.repo().transaction()
    |> case do
      {:ok, %{^result_id => result}} ->
        {:ok, result}

      {:error, _stage, error, _context} ->
        {:error, error}
    end
  end

  def get_public_url(%Blob{key: key}) do
    Upload.Storage.get_public_url(key)
  end

  @doc """
  Returns a signed URL which can be used to provide temporary, time-limited
  access to a specific object.

  Returns the public URL when not using S3 as the storage backend.
  """
  def get_signed_url(%Blob{key: key}) do
    Upload.Storage.get_signed_url(key)
  end
end
