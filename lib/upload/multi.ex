defmodule Upload.Multi do
  @moduledoc """
  Functions to help uploading and removing of blobs as part of an `Ecto.Multi`.
  """

  alias Ecto.Association.NotLoaded
  alias Ecto.Multi
  alias Upload.Blob
  alias Upload.Storage

  @doc """
  Upload a blob to storage.
  """
  @spec upload(Multi.t(), Multi.name(), Blob.t()) :: Multi.t()
  def upload(multi, name, %Blob{key: key, path: path} = blob)
      when is_binary(key) and is_binary(path) do
    Multi.run(multi, name, fn _repo, _ctx -> do_upload(blob) end)
  end

  @spec upload(Multi.t(), Multi.name(), Multi.fun(Blob.t())) :: Multi.t()
  def upload(multi, name, fun) when is_function(fun) do
    Multi.run(multi, name, fn _repo, ctx -> ctx |> fun.() |> do_upload() end)
  end

  defp do_upload(nil), do: {:ok, nil}
  defp do_upload(%NotLoaded{} = blob), do: {:ok, blob}
  defp do_upload(%Blob{path: nil} = blob), do: {:ok, blob}

  defp do_upload(%Blob{path: path, key: key} = blob) when is_binary(key) do
    with :ok <- Storage.upload(path, key),
         do: {:ok, blob}
  end

  @doc """
  Remove a blob and it's variants from storage.
  """
  @spec purge(Multi.t(), Multi.name(), Blob.t()) :: Multi.t()
  def purge(multi, name, %Blob{key: key} = blob) when is_binary(key) do
    Multi.run(multi, name, fn _repo, _ctx -> do_purge(blob) end)
  end

  @spec purge(Multi.t(), Multi.name(), Multi.fun(Blob.t())) :: Multi.t()
  def purge(multi, name, fun) when is_function(fun) do
    Multi.run(multi, name, fn _repo, ctx -> ctx |> fun.() |> do_purge() end)
  end

  defp do_purge(nil), do: {:ok, nil}

  defp do_purge(%Blob{key: key} = blob) when is_binary(key) do
    with :ok <- remove_variants(blob),
         :ok <- Storage.delete(key),
         do: {:ok, blob}
  end

  defp remove_variants(blob) do
    repo = Upload.Config.repo()
    blob = repo.preload(blob, :variants)

    Enum.each(blob.variants, fn variant ->
      {:ok, _blob_variant} = do_purge(variant)
    end)

    :ok
  end

  def remove_existing_variant(multi, original_blob, variant) do
    case Upload.get_variant(original_blob, variant) do
      nil ->
        multi

      existing_variant_blob ->
        purge(multi, :remove_existing_variant, existing_variant_blob)
    end
  end

  def download_and_insert_variant(multi, original_blob, variant, transform_fn) do
    Multi.run(multi, "download_and_insert_#{variant}", fn repo, _ ->
      with {:ok, blob_path} <- create_random_file(),
           :ok <- Upload.Storage.download(original_blob.key, blob_path),
           {:ok, variant_path} <- create_random_file(),
           :ok <- transform_fn.(blob_path, variant_path, variant),
           :ok <- cleanup(blob_path),
           {:ok, blob} <- insert_variant(repo, original_blob, variant, variant_path),
           :ok <- cleanup(variant_path) do
        {:ok, blob}
      end
    end)
  end

  defp insert_variant(repo, original_blob, variant, variant_path) do
    if original_blob.variant do
      raise "A variant of a blob can not be created for a blob that is already a variant"
    end

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

    {:ok, repo.insert(changeset)}
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
end
