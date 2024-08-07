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

  @doc """
  Returns the variant for a given `Upload.Blob` and the variant identifier or `nil` if it
  does not exist.

  ## Example

      iex> Upload.get_variant(person.avatar, :small)
      %Blob{}

  """
  @spec get_variant(Blob.t(), variant_id()) :: nil | Blob.t()
  def get_variant(%Blob{id: blob_id}, variant) do
    repo = Upload.Config.repo()

    Blob
    |> where([blob], blob.original_blob_id == ^blob_id and blob.variant == ^to_string(variant))
    |> repo.one()
  end

  @doc """
  Creates and uploads a single variant of a blob.

  Calling this multiple times is not the optimal for creating multiple variants
  of a blob at once since this function would download the original blob once
  per variant. See `create_multiple_variants/3`.

  ## Example

      iex> create_variant(original_blob, :small, &transform_fn/3)
      {:ok, %Blob{}}
  """
  @spec create_variant(Blob.t(), String.t(), any()) :: {:ok, Blob.t()} | {:error, any()}
  def create_variant(original_blob, variant, transform_fn) when is_function(transform_fn, 3) do
    repo = Upload.Config.repo()
    variant = to_string(variant)

    Ecto.Multi.new()
    |> Upload.Multi.remove_existing_variant(original_blob, variant)
    |> Upload.Multi.download_and_insert_variant(original_blob, variant, transform_fn)
    |> repo.transaction()
    |> case do
      {:ok, multi_result} -> {:ok, Map.fetch!(multi_result, "download_and_insert_#{variant}")}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Creates multiple versions of a blob after downloading the source blob once.
  Useful for creating multiple versions of a photo for example.

  ## Example

      iex> create_multiple_variants(blob, [:small, :large], &transform_fn/3)
      {:ok, [%Blob{...}, %Blob{...}]}
  """
  @spec create_multiple_variants(Blob.t(), [variant_id()], any()) ::
          {:ok, [Blob.t()]} | {:error, String.t(), any()}
  def create_multiple_variants(original_blob, variants, transform_fn)
      when is_function(transform_fn, 3) do
    variants = Enum.map(variants, &to_string/1)
    repo = Upload.Config.repo()
    multi = Ecto.Multi.new()

    variants
    |> Enum.reduce(multi, fn variant, multi ->
      multi
      |> Upload.Multi.remove_existing_variant(original_blob, variant)
      |> Upload.Multi.download_and_insert_variant(original_blob, variant, transform_fn)
    end)
    |> repo.transaction()
    |> case do
      {:ok, multi_result} ->
        {:ok, Map.values(multi_result)}

      {:error, stage, error, _} ->
        {:error, stage, error}
    end
  end

  @doc """
  Set the visiblity of a `Blob` using the struct or it's key.

  > #### Note {: .warning}
  >
  > This only applies when Upload is configured to use S3.

  Supported canned access control lists for Amazon S3 are:

  | ACL                          | Permissions Added to ACL                                                        |
  |------------------------------|---------------------------------------------------------------------------------|
  | private                      | Owner gets `FULL_CONTROL`. No one else has access rights (default).             |
  | public_read                  | Owner gets `FULL_CONTROL`. The `AllUsers` group gets READ access.               |
  | public_read_write            | Owner gets `FULL_CONTROL`. The `AllUsers` group gets `READ` and `WRITE` access. Granting this on a bucket is generally not recommended. |
  | authenticated_read           | Owner gets `FULL_CONTROL`. The `AuthenticatedUsers` group gets `READ` access.   |
  | bucket_owner_read            | Object owner gets `FULL_CONTROL`. Bucket owner gets `READ` access.              |
  | bucket_owner_full_control    | Both the object owner and the bucket owner get `FULL_CONTROL` over the object.  |

  ## Example

      iex> Upload.put_access_control_list(person.avatar, :public_read)
      :ok
  """
  @spec put_access_control_list(Blob.t() | Blob.key(), String.t()) :: :ok | {:error, term()}
  def put_access_control_list(%Blob{key: key} = _blob, canned_acl) do
    put_access_control_list(key, canned_acl)
  end

  def put_access_control_list(key, canned_acl) do
    Upload.Storage.put_access_control_list(key, [{:acl, canned_acl}])
  end
end
