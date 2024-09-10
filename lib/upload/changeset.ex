defmodule Upload.Changeset do
  @moduledoc """
  Functions for use with changesets to cast and validate attachments.

  These functions will not perform an upload of the `Upload.Blob` as they only
  create and validate the database record. For synchronizing uploads remotely
  see `Upload.Multi.handle_changes/6`

  ```elixir
  schema "people" do
    belongs_to(:avatar, Upload.Blob, on_replace: :delete, type: :binary_id)
  end

  %Person{}
  |> Person.changeset(%{avatar: upload})
  |> cast_attachment(:avatar, required: true)
  |> validate_attachment_type(:avatar, allow: ["image/png"])
  ```
  """
  import Ecto.Changeset

  @type changeset :: Ecto.Changeset.t()
  @type field :: atom
  @type error :: binary | Ecto.Changeset.error()
  @type validation :: (any -> [error])
  @type size :: {number, :byte | :kilobyte | :megabyte | :gigabyte | :terabyte}
  @type key_function :: (changeset -> String.t())

  @type cast_opts :: [{:invalid_message, binary} | {:key_function, key_function}]
  @type size_opts :: [{:less_than, size} | {:message, binary}]
  @type type_opts :: [{:allow, [binary]} | {:forbid, [binary]} | {:message, binary}]

  @unit_conversions %{
    byte: 1,
    kilobyte: 1.0e3,
    megabyte: 1.0e6,
    gigabyte: 1.0e9,
    terabyte: 1.0e12
  }

  @spec put_attachment(changeset(), field(), Plug.Upload.t() | Upload.Stat.t(), String.t()) ::
          changeset()
  def put_attachment(changeset, field, %Plug.Upload{} = upload, key) do
    put_attachment(changeset, field, Upload.stat!(upload), key)
  end

  def put_attachment(changeset, field, %Upload.Stat{} = stat, key) do
    put_assoc(changeset, field, Upload.Blob.change_blob(stat, key))
  end

  @spec put_attachment(changeset(), field(), Upload.Blob.t()) :: changeset()
  def put_attachment(changeset, field, %Upload.Blob{} = blob) do
    put_assoc(changeset, field, blob)
  end

  @doc """
  Adds an attachment to the changeset changes.

  ## Options

    * `:required` - Require the attachment.
    * `:key_function` - A 1-arity function that is given the changeset and is
      expected to return the path of the attachment in external storage without
      the file type extension.

  ## Example

      iex> Upload.Changeset.cast_attachment(changeset, :avatar)

      iex> Upload.Changeset.cast_attachment(changeset, :avatar, required: true, key_function: &key_function/1)

  """
  @spec cast_attachment(changeset(), field(), cast_opts()) :: changeset()
  def cast_attachment(changeset, field, opts \\ []) do
    key_function = key_function_from_opts(opts)

    case Map.fetch(changeset.params, to_string(field)) do
      {:ok, %Plug.Upload{} = upload} ->
        put_attachment(changeset, field, upload, key_function.(changeset))

      {:ok, path} when is_binary(path) ->
        case Upload.stat(path) do
          {:error, _error} ->
            message = Keyword.get(opts, :invalid_message, "is invalid")
            meta = [validation: :assoc, type: :map]
            add_error(changeset, field, message, meta)

          {:ok, stat} ->
            put_attachment(changeset, field, stat, key_function.(changeset))
        end

      {:ok, nil} ->
        if Keyword.get(opts, :required, false) do
          message = Keyword.get(opts, :required_message, "can't be blank")
          meta = [validation: :required]
          add_error(changeset, field, message, meta)
        else
          put_assoc(changeset, field, nil)
        end

      {:ok, _other} ->
        message = Keyword.get(opts, :invalid_message, "is invalid")
        meta = [validation: :assoc, type: :map]
        add_error(changeset, field, message, meta)

      :error ->
        changeset
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

  @spec validate_attachment(changeset, field, field, validation) :: changeset
  def validate_attachment(changeset, field, blob_field, validation) do
    validate_change(changeset, field, fn _, blob_changeset ->
      case get_change(blob_changeset, blob_field) do
        nil ->
          []

        value ->
          validation.(value)
      end
    end)
  end

  @doc """
  Require that the attachment is of a specific MIME type. This is determined by
  looking at the file's contents and can be trusted.

  ## Example

      iex> validate_attachment_type(changeset, :avatar, allow: ["image/jpeg", "image/png"])

  """
  @spec validate_attachment_type(changeset(), field(), type_opts()) :: changeset()
  def validate_attachment_type(changeset, field, opts) do
    {message, opts} = Keyword.pop(opts, :message, "is not a supported file type")

    validate_attachment(changeset, field, :content_type, fn type ->
      allowed_types = Keyword.fetch!(opts, :allow)

      if type in allowed_types,
        do: [],
        else: [{field, {message, allowed: allowed_types}}]
    end)
  end

  @doc """
  Require that the attachment size is in a specific range.

  ## Example

      iex> validate_attachment_size(changeset, :avatar, smaller_than: {1, :megabyte})

  """
  @spec validate_attachment_size(changeset, field, size_opts) :: changeset
  def validate_attachment_size(changeset, field, opts) do
    size = {number, unit} = Keyword.fetch!(opts, :smaller_than)
    message = Keyword.get(opts, :message, "must be smaller than %{number} %{unit}(s)")
    max_byte_size = to_bytes(size)

    validate_attachment(changeset, field, :byte_size, fn
      byte_size when byte_size < max_byte_size -> []
      _ -> [{field, {message, number: number, unit: unit}}]
    end)
  end

  for {unit, multiplier} <- @unit_conversions do
    defp to_bytes({n, unquote(unit)}), do: n * unquote(multiplier)
  end
end
