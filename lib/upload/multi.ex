defmodule Upload.Multi do
  @moduledoc """
  Functions to help uploading and removing of blobs as part of an `Ecto.Multi`.
  """

  alias Ecto.Association.NotLoaded
  alias Ecto.Multi
  alias Upload.Blob
  alias Upload.Logger
  alias Upload.Storage

  @doc """
  Upload a blob to storage.
  """
  @spec upload(Multi.t(), Multi.name(), Blob.t()) :: Multi.t()
  def upload(multi, name, %Blob{key: key, path: path} = blob)
      when is_binary(key) and is_binary(path) do
    Multi.run(multi, name, fn _repo, _ctx -> do_upload(blob) end)
  end

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
    Upload.Logger.info("Uploading #{key}")

    with :ok <- Storage.upload(path, key),
         do: {:ok, blob}
  end

  @doc """
  Upload multiple variants as part of a multi.
  """
  def upload_variants(multi, name, fun, variants, transform_fn, opts \\ [])
      when is_function(fun) do
    Multi.run(multi, name, fn _repo, ctx ->
      original_blob = ctx |> fun.()

      Upload.create_multiple_variants(original_blob, variants, transform_fn, opts)
    end)
  end

  @doc """
  Upload a variant as part of a multi.
  """
  def upload_variant(multi, name, fun, variant, transform_fn, opts \\ []) when is_function(fun) do
    Multi.run(multi, name, fn _repo, ctx ->
      original_blob = ctx |> fun.()

      Upload.create_variant(original_blob, variant, transform_fn, opts)
    end)
  end

  @doc """
  Uploads and attaches a blob to a record using a Multi.
  """
  def handle_changes(multi, name, subject, changeset, field, opts \\ []) do
    key_function = key_function_from_opts(opts)

    Multi.run(multi, name, fn repo, changes ->
      # This code is run after the record in inserted in the Multi pipeline.
      # We can use the record ID here to upload the photo.
      record = Map.get(changes, subject)

      if is_nil(record) do
        raise ArgumentError,
              "The key '#{subject}' is not in the multi changes: #{inspect(changes)}"
      end

      record = repo.preload(record, [field])

      record_changeset =
        record
        |> Ecto.Changeset.cast(%{field => Map.get(changeset.params, to_string(field))}, [])
        |> Upload.Changeset.cast_attachment(field,
          key_function: fn _ ->
            key_function.(record)
          end
        )

      record_changeset.changes
      |> Enum.reduce(Ecto.Multi.new(), fn {changed_field, change}, multi ->
        # Deletes if the change is 'nil', uploads otherwise.
        handle_change({changed_field, change}, multi, changeset)
      end)
      |> Multi.update("#{field}_attach_blob", record_changeset)
      |> repo.transaction()
      |> case do
        {:ok, result} -> {:ok, result["#{field}_attach_blob"]}
        error -> error
      end
    end)
  end

  defp key_function_from_opts(opts) do
    case Keyword.get(opts, :key_function) do
      nil ->
        nil

      key_function when is_function(key_function, 1) ->
        key_function

      unexpected ->
        raise ArgumentError,
              "key_function must be a function of arity 1. Got #{inspect(unexpected)}"
    end
  end

  # We're setting the upload field to nil so let's check
  # if the existing field is set and delete it if so.
  defp handle_change({field, nil}, multi, changeset) do
    case Map.get(changeset.data, field) do
      %Upload.Blob{} = blob -> delete_blob(multi, :delete_blob, blob)
      _ -> multi
    end
  end

  # We're setting the upload field so let's check
  # if the existing field is set and delete it if so.
  defp handle_change({field, change}, multi, changeset) do
    multi = handle_change({field, nil}, multi, changeset)

    blob = Ecto.Changeset.apply_changes(change)

    upload(multi, field, blob)
  end

  @doc """
  Remove a blob and it's variants from storage.
  """
  @spec delete_blob(Multi.t(), Multi.name(), Blob.t()) :: Multi.t()
  def delete_blob(multi, name, %Blob{key: key} = blob) when is_binary(key) do
    Multi.run(multi, name, fn _repo, _ctx -> do_delete(blob) end)
  end

  @spec delete_blob(Multi.t(), Multi.name(), Multi.fun(Blob.t())) :: Multi.t()
  def delete_blob(multi, name, fun) when is_function(fun) do
    Multi.run(multi, name, fn _repo, ctx -> ctx |> fun.() |> do_delete() end)
  end

  @spec delete_blob(Multi.t(), Multi.name(), nil) :: Multi.t()
  def delete_blob(multi, _name, nil) do
    multi
  end

  defp do_delete(nil), do: {:ok, nil}

  defp do_delete(%Blob{key: key} = blob) when is_binary(key) do
    Logger.info("Removing blob #{blob.key}")

    with :ok <- remove_variants(blob),
         :ok <- Storage.delete(key),
         do: {:ok, blob}
  end

  defp remove_variants(blob) do
    repo = Upload.Config.repo()
    blob = repo.preload(blob, :variants)

    Enum.each(blob.variants, fn variant ->
      Logger.info("Removing variant #{variant.variant} for key #{blob.key}")

      {:ok, _blob_variant} = do_delete(variant)
    end)

    :ok
  end

  def remove_existing_variant(multi, original_blob, variant) do
    case Upload.get_variant(original_blob, variant) do
      nil ->
        multi

      existing_variant_blob ->
        delete_blob(multi, :remove_existing_variant, existing_variant_blob)
    end
  end

  def create_multiple_variants(multi, original_blob, variants, transform_fn, opts \\ [])
      when is_function(transform_fn, 3) do
    variants = Enum.map(variants, &to_string/1)
    formats = Keyword.get(opts, :formats, [:"image/jpeg"])

    Enum.reduce(variants, multi, fn variant, multi ->
      multi = Upload.Multi.remove_existing_variant(multi, original_blob, variant)

      Enum.reduce(formats, multi, fn format, multi ->
        Upload.Multi.download_and_insert_variant(
          multi,
          original_blob,
          variant,
          transform_fn,
          format
        )
      end)
    end)
  end

  def download_and_insert_variant(multi, original_blob, variant, transform_fn, format) do
    Multi.run(multi, "download_and_insert_#{variant}_#{format}", fn repo, _ ->
      with {:ok, blob_path} <- create_random_file(),
           :ok <- download_file(original_blob.key, blob_path),
           {:ok, variant_path} <-
             call_transform_fn(transform_fn, blob_path, variant, format),
           :ok <- cleanup(blob_path),
           {:ok, blob} <- insert_variant(repo, original_blob, variant, variant_path),
           {:ok, _} <- do_upload(blob),
           :ok <- cleanup(variant_path) do
        {:ok, blob}
      else
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp call_transform_fn(transform_fn, blob_path, variant, format) do
    case :timer.tc(transform_fn, [blob_path, variant, format]) do
      {microseconds, {:ok, path}} ->
        Upload.Logger.info(
          "Processed image variant '#{variant}' with format '#{format}' in #{microseconds / 1_000}ms"
        )

        {:ok, path}

      {_time, {:error, error}} ->
        {:error, error}

      {_time, unexpected} ->
        raise "Expected upload transform function to return {:ok, path} or {:error, error}, got: #{inspect(unexpected)}"
    end
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
      |> Map.put(:key, original_key_without_ext <> "/" <> to_string(variant))
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
    case File.rm(path) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, %File.Error{path: path, reason: reason, action: "remove temporary file"}}
    end
  end

  defp download_file(key, path) do
    case Upload.Storage.download(key, path) do
      :ok -> :ok
      {:error, reason} -> {:error, %Upload.DownloadError{reason: reason, key: key, path: path}}
    end
  end
end
