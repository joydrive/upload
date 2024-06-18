defmodule Upload.Changeset do
  @moduledoc """
  Functions to use with changesets to upload an attachment on a schema.

  ```elixir
  %Person{}
  |> Person.changeset(%{avatar: upload})
  |> cast_attachment(:avatar, required: true)
  |> validate_attachment_type(:avatar, allow: ["image/png"])
  ```
  """

  import Ecto.Changeset

  @type changeset :: Ecto.t()
  @type field :: atom
  @type error :: binary | Changeset.error()
  @type validation :: (any -> [error])
  @type size :: {number, :byte | :kilobyte | :megabyte | :gigabyte | :terabyte}

  @type cast_opts :: [{:invalid_message, binary}]
  @type size_opts :: [{:less_than, size} | {:message, binary}]
  @type type_opts :: [{:allow, [binary]} | {:forbid, [binary]} | {:message, binary}]

  @unit_conversions %{
    byte: 1,
    kilobyte: 1.0e3,
    megabyte: 1.0e6,
    gigabyte: 1.0e9,
    terabyte: 1.0e12
  }

  @spec put_attachment(changeset(), field(), Plug.Upload.t(), String.t()) :: changeset()
  defp put_attachment(changeset, field, %Plug.Upload{} = upload, key) do
    put_attachment(changeset, field, Upload.stat!(upload), key)
  end

  @spec put_attachment(changeset(), field(), Upload.Stat.t(), String.t()) :: changeset()
  defp put_attachment(changeset, field, %Upload.Stat{} = stat, key) do
    put_assoc(changeset, field, Upload.Blob.change_blob(stat, key))
  end

  @spec put_attachment(changeset(), field(), Ecto.Changeset.t(), String.t()) :: changeset()
  defp put_attachment(changeset, field, %Ecto.Changeset{} = blob_changeset, key) do
    put_assoc(changeset, field, blob_changeset |> put_change(:key, key))
  end

  @spec put_attachment(changeset(), field(), Upload.Blob.t()) :: changeset()
  def put_attachment(changeset, field, %Upload.Blob{} = blob) do
    put_assoc(changeset, field, blob)
  end

  @spec cast_attachment(changeset(), field(), cast_opts()) :: changeset()
  def cast_attachment(changeset, field, opts \\ []) do
    key =
      case Keyword.get(opts, :key_function) do
        nil -> nil
        key_function when is_function(key_function, 1) -> key_function.(changeset)
        _ -> raise ArgumentError, "key_function must be a function of arity 1."
      end

    case Map.fetch(changeset.params, to_string(field)) do
      {:ok, %Plug.Upload{} = upload} ->
        put_attachment(changeset, field, upload, key)

      {:ok, nil} ->
        if Keyword.get(opts, :required, false) do
          message = Keyword.get(opts, :required_message, "can't be blank")
          meta = [validation: :required]
          add_error(changeset, field, message, meta)
        else
          # delete here?
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

  @spec validate_attachment_type(changeset, field, type_opts) :: changeset
  def validate_attachment_type(changeset, field, opts) do
    {message, opts} = Keyword.pop(opts, :message, "is not a supported file type")

    validate_attachment(changeset, field, :content_type, fn type ->
      allowed_types = Keyword.fetch!(opts, :allow)

      if type in allowed_types,
        do: [],
        else: [{field, {message, allowed: allowed_types}}]
    end)
  end

  @spec validate_attachment_image_dimensions(changeset, field, size_opts) :: changeset
  def validate_attachment_image_dimensions(_changeset, _field, _opts) do
    # TODO
  end

  @spec validate_attachment_size(changeset, field, size_opts) :: changeset
  def validate_attachment_size(changeset, field, opts) do
    size = {number, unit} = Keyword.fetch!(opts, :smaller_than)
    message = Keyword.get(opts, :message, "must be smaller than %{number} %{unit}(s)")
    max_byte_size = to_bytes(size)

    validate_attachment(changeset, field, :byte_size, fn
      byte_size when byte_size < max_byte_size -> []
      _ -> [{message, number: number, unit: unit}]
    end)
  end

  for {unit, multiplier} <- @unit_conversions do
    defp to_bytes({n, unquote(unit)}), do: n * unquote(multiplier)
  end
end
