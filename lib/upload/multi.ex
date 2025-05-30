defmodule Upload.Multi do
  @moduledoc """
  Functions for uploading, creating variants, and removing of blobs as part of
  an `Ecto.Multi`.
  """

  alias Ecto.Association.NotLoaded
  alias Ecto.Multi
  alias Upload.Blob
  alias Upload.Storage

  @doc """
  Upload a blob to storage.

  ## Options

  - `canned_acl` - The canned ACL to use with S3 if using S3 as the storage
    backend.

  """
  def upload_blob(multi, name, blob, opts \\ [])

  @spec upload_blob(Multi.t(), Multi.name(), Blob.t()) :: Multi.t()
  def upload_blob(multi, name, %Blob{key: key, path: path} = blob, opts)
      when is_binary(key) and is_binary(path) do
    Multi.run(multi, name, fn _repo, _ctx -> do_upload_blob(blob, opts) end)
  end

  @spec upload_blob(Multi.t(), Multi.name(), Multi.fun(Blob.t())) :: Multi.t()
  def upload_blob(multi, name, fun, opts) when is_function(fun) do
    Multi.run(multi, name, fn _repo, ctx -> ctx |> fun.() |> do_upload_blob(opts) end)
  end

  defp do_upload_blob(nil, _opts), do: {:ok, nil}
  defp do_upload_blob(%NotLoaded{} = blob, _opts), do: {:ok, blob}
  defp do_upload_blob(%Blob{path: nil} = blob, _opts), do: {:ok, blob}

  defp do_upload_blob(%Blob{path: path, key: key} = blob, opts) when is_binary(key) do
    metadata = %{key: key, path: path}

    :telemetry.span(
      [:upload, :storage_upload],
      metadata,
      fn ->
        {with(
           :ok <- Storage.upload(path, key),
           :ok <- Upload.put_access_control_list(blob, opts[:canned_acl] || :private),
           do: {:ok, blob}
         ), metadata}
      end
    )
  end

  @doc """
  Upload multiple variants as part of an `Ecto.Multi`.

   ## Options

  - `canned_acl` - The canned ACL to use with S3 if using S3 as the storage
    backend.
  """
  def upload_variants(multi, name, fun, variants, transform_fn, opts \\ [])
      when is_function(fun) do
    Multi.run(multi, name, fn _repo, ctx ->
      original_blob = ctx |> fun.()

      Upload.create_variants(original_blob, variants, transform_fn, opts)
    end)
  end

  @doc """
  Upload a variant as part of an `Ecto.Multi`.
  """
  def upload_variant(multi, name, fun, variant, transform_fn, opts \\ []) when is_function(fun) do
    Multi.run(multi, name, fn _repo, ctx ->
      original_blob = ctx |> fun.()

      Upload.create_variant(original_blob, variant, transform_fn, opts)
    end)
  end

  @doc """
  Uploads and attaches a blob to a record using an `Ecto.Multi`. This should be
  used inside of your Phoenix Contexts to handle uploads and deletes.

  If the `field` change is `nil` in the changeset, it will be deleted remotely
  and in your database. If the `field` change in the changeset is an uploadable
  type such as a `Plug.Upload` or file path, it will be uploaded, replacing any
  existing associated upload.

  ## Example

      defp insert_person(changeset) do
        Ecto.Multi.new()
        |> Ecto.Multi.insert(:person, changeset)
        |> Upload.Multi.handle_changes(:upload_avatar, :person, changeset, :avatar, key_function: &key_function/1)
        |> Repo.transaction()
      end

  ## Options

  - `canned_acl` - The canned ACL to use with S3 if using S3 as the storage
    backend.
  - `key_function` - A function which recieves the schema specified by `subject`
    from the multi and must return a file storage path without the extension.
  - `validate` - A 2 arity function which recieves the changeset and the field
    being modified. Additional changeset logic can be added here, such as
    validating the file format or size of the upload.
  """
  def handle_changes(multi, name, subject, changeset, field, opts \\ []) do
    Multi.run(multi, name, fn repo, changes ->
      # This code is run after the record in inserted in the Multi pipeline.
      # We can use the record ID here to upload the photo.
      record = Map.get(changes, subject)

      if is_nil(record) do
        raise ArgumentError,
              "The key '#{subject}' is not in the multi changes: #{inspect(changes)}"
      end

      record = repo.preload(record, [field])

      handle_changeset_changes(repo, changeset, field, record, changes, opts)
    end)
  end

  defp handle_changeset_changes(repo, changeset, field, record, multi_changes, opts) do
    key = key_function_from_opts(opts).(record)
    validate_function = validate_function_from_opts(opts)

    case Map.get(changeset.params || %{}, to_string(field), :no_change) do
      :no_change ->
        {:ok, record}

      new_value ->
        record_changeset =
          record
          |> Ecto.Changeset.cast(%{field => new_value}, [])
          |> Upload.Changeset.cast_attachment(field,
            key_function: fn _ -> key end
          )
          |> validate_function.(field)

        multi =
          maybe_delete_existing_by_key(
            Ecto.Multi.new(),
            repo,
            record_changeset,
            field
          )

        record_changeset.changes
        |> Enum.reduce(multi, fn {changed_field, change}, multi ->
          # Deletes if the change is 'nil', uploads otherwise.
          handle_change({changed_field, change}, multi, changeset, multi_changes, opts)
        end)
        |> Multi.update("#{field}_attach_blob", record_changeset)
        |> repo.transaction()
        |> case do
          {:ok, result} -> {:ok, result["#{field}_attach_blob"]}
          {:error, _stage, changeset, _rest} -> {:error, changeset}
        end
    end
  end

  # If there's an existing blob with the same key, the call to put_assoc for the
  # blob field will not delete it since it's not associated. This code ensures
  # that if it's not associated we will delete it with a separate database query
  # so a foreign key constraint on the key is not raised.
  defp maybe_delete_existing_by_key(multi, repo, record_changeset, field) do
    existing_assoc? = not is_nil(Map.get(record_changeset.data, field))

    key_with_extension =
      Map.get(Ecto.Changeset.get_field(record_changeset, field) || %{}, :key)

    delete_existing_by_key(multi, repo, key_with_extension, existing_assoc?)
  end

  defp delete_existing_by_key(multi, _, _, true = _existing_assoc?), do: multi
  defp delete_existing_by_key(multi, _, nil, _), do: multi

  defp delete_existing_by_key(multi, repo, key, false = _existing_assoc?) do
    existing_blob = repo.get_by(Upload.Blob, key: key)

    if existing_blob do
      delete_blob(multi, "remove_existing_blob", existing_blob)
    else
      multi
    end
  end

  defp validate_function_from_opts(opts) do
    case Keyword.get(opts, :validate) do
      nil ->
        fn changeset, _field -> changeset end

      validate_function when is_function(validate_function, 2) ->
        validate_function

      unexpected ->
        raise ArgumentError,
              "validate function must be a function of arity 2. Got #{inspect(unexpected)}"
    end
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
  defp handle_change({field, nil}, multi, changeset, _multi_changes, _opts) do
    case Map.get(changeset.data, field) do
      %Upload.Blob{} = blob -> delete_blob(multi, :delete_blob, blob)
      _ -> multi
    end
  end

  # We're setting the upload field so let's check
  # if the existing field is set and delete it if so.
  defp handle_change({field, change}, multi, changeset, multi_changes, opts) do
    multi = handle_change({field, nil}, multi, changeset, multi_changes, opts)

    blob = Ecto.Changeset.apply_changes(change)

    multi
    |> upload_blob(field, blob, opts)
    |> on_upload_callback(field, multi_changes, opts)
  end

  defp on_upload_callback(multi, field, multi_changes, opts) do
    if opts[:on_upload] do
      Multi.run(multi, "#{field}_on_upload", fn repo, changes ->
        opts[:on_upload].(repo, Map.merge(multi_changes, changes))
      end)
    else
      multi
    end
  end

  @doc """
  Remove an `Upload.Blob` and it's variants from storage.

  ## Example

  ```elixir
  defp delete_person(person) do
    Ecto.Multi.new()
    |> Ecto.Multi.delete(:person, person)
    |> Upload.Multi.delete_blob(:avatar, fn ctx -> ctx.person.avatar end)
    |> Repo.transaction()
  end
  ```
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
    repo = Upload.Config.repo()

    with :ok <- remove_variants(blob),
         :ok <- storage_delete_with_telemetry(key) do
      repo.delete(blob)
    end
  end

  defp storage_delete_with_telemetry(key) do
    metadata = %{key: key}

    :telemetry.span(
      [:upload, :storage_delete],
      metadata,
      fn ->
        {Storage.delete(key), metadata}
      end
    )
  end

  defp remove_variants(blob) do
    repo = Upload.Config.repo()
    blob = repo.preload(blob, :variants)

    Enum.each(blob.variants, fn variant ->
      {:ok, _blob_variant} = do_delete(variant)
    end)

    :ok
  end

  def remove_variants(multi, original_blob, variant, formats) do
    Enum.reduce(formats, multi, fn format, multi ->
      remove_variant(multi, original_blob, variant, format)
    end)
  end

  def remove_variant(multi, original_blob, variant, format) do
    case Upload.get_variant(original_blob, variant, format) do
      nil ->
        multi

      existing_variant_blob ->
        delete_blob(multi, "remove_variant_#{variant}_#{format}", existing_variant_blob)
    end
  end

  def create_variant(multi, original_blob, variant, transform_fn, opts \\ [])

  @doc """
  Creates and uploads a single variant of an `Upload.Blob` inside of an `Ecto.Multi`.

  ## Example

  ```elixir
  Ecto.Multi.new()
  |> Ecto.Multi.insert(:person, changeset)
  |> Upload.Multi.handle_changes(:upload_avatar, :person, changeset, :avatar, key_function: key_function)
  |> Upload.Multi.create_variant(fn ctx -> ctx.person.avatar end, :small, transform_fn: &transform_fn/3)
  ```

  ## Options

  - `canned_acl` - The canned ACL to use with S3 if using S3 as the storage
    backend.

  """
  def create_variant(multi, fun, variant, transform_fn, opts)
      when is_function(fun, 1) and is_function(transform_fn, 3) do
    repo = Upload.Config.repo()

    Multi.run(multi, opts[:multi_name] || :create_variants, fn _repo, ctx ->
      case fun.(ctx) do
        nil ->
          {:ok, nil}

        %Blob{} = original_blob ->
          Multi.new()
          |> create_variant(original_blob, variant, transform_fn, opts)
          |> repo.transaction()
      end
    end)
  end

  def create_variant(multi, original_blob, variant, transform_fn, opts) do
    variant = to_string(variant)
    formats = Keyword.get(opts, :formats, [:"image/jpeg"])

    multi = remove_variants(multi, original_blob, variant, formats)

    Enum.reduce(formats, multi, fn format, multi ->
      download_and_insert_variant(
        multi,
        original_blob,
        variant,
        transform_fn,
        format,
        opts
      )
    end)
  end

  def create_variants(multi, fun, variants, transform_fn, opts \\ [])

  @doc """
  Creates and uploads multiple variants of an `Upload.Blob` inside of an `Ecto.Multi`.

  ## Example

  ```elixir
  Ecto.Multi.new()
  |> Ecto.Multi.insert(:person, changeset)
  |> Upload.Multi.handle_changes(:upload_avatar, :person, changeset, :avatar, key_function: key_function)
  |> Upload.Multi.create_variants(fn ctx -> ctx.person.avatar end, [:small, :large], transform_fn: &transform_fn/3)
  ```

  ## Options

  - `canned_acl` - The canned ACL to use with S3 if using S3 as the storage
    backend.
  """
  def create_variants(multi, fun, variants, transform_fn, opts)
      when is_function(fun, 1) and is_function(transform_fn, 3) do
    repo = Upload.Config.repo()

    Multi.run(multi, opts[:multi_name] || :create_variants, fn _repo, ctx ->
      case fun.(ctx) do
        nil ->
          {:ok, nil}

        %Blob{} = original_blob ->
          Multi.new()
          |> create_variants(original_blob, variants, transform_fn, opts)
          |> repo.transaction()
      end
    end)
  end

  def create_variants(multi, original_blob, variants, transform_fn, opts)
      when is_function(transform_fn, 3) do
    variants = Enum.map(variants, &to_string/1)
    formats = Keyword.get(opts, :formats, [:"image/jpeg"])

    Enum.reduce(variants, multi, fn variant, multi ->
      multi = remove_variants(multi, original_blob, variant, formats)

      Enum.reduce(formats, multi, fn format, multi ->
        download_and_insert_variant(
          multi,
          original_blob,
          variant,
          transform_fn,
          format,
          opts
        )
      end)
    end)
  end

  defp download_and_insert_variant(
         multi,
         original_blob,
         variant,
         transform_fn,
         format,
         opts
       ) do
    Multi.run(multi, "download_and_insert_#{variant}_#{format}", fn repo, _ ->
      with {:ok, blob_path} <- create_random_file(),
           :ok <- download_file(original_blob.key, blob_path),
           {:ok, variant_path} <-
             call_transform_fn(original_blob.key, transform_fn, blob_path, variant, format),
           :ok <- cleanup(blob_path),
           {:ok, blob} <- insert_variant(repo, original_blob, variant, variant_path),
           {:ok, _} <- do_upload_blob(blob, opts),
           :ok <- cleanup(variant_path) do
        {:ok, blob}
      else
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp call_transform_fn(original_blob_key, transform_fn, blob_path, variant, format) do
    metadata = %{
      original_blob_key: original_blob_key,
      blob_path: blob_path,
      variant: variant,
      format: format
    }

    case :telemetry.span(
           [:upload, :transform],
           metadata,
           fn ->
             {transform_fn.(blob_path, variant, format), metadata}
           end
         ) do
      {:ok, path} ->
        {:ok, path}

      {:error, error} ->
        {:error, error}

      unexpected ->
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
    metadata = %{key: key, path: path}

    :telemetry.span(
      [:upload, :storage_download],
      metadata,
      fn ->
        result =
          case Upload.Storage.download(key, path) do
            :ok ->
              :ok

            {:error, reason} ->
              {:error, %Upload.DownloadError{reason: reason, key: key, path: path}}
          end

        {result, metadata}
      end
    )
  end
end
