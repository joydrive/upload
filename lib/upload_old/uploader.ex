defmodule UploadOld.Uploader do
  @moduledoc """
  This is a behaviour that defines how an uploader should behave. It
  comes in handy if you want to validate uploads or transform files
  before uploading.

  ### Example

     defmodule MyUploader do
        use Upload.Uploader

        def cast(file) do
          with {:ok, upload} <- Upload.cast(file) do
            extension = Upload.get_extension(upload)

            if Enum.member?(~w(.png), extension) do
              {:ok, upload}
            else
              {:error, "not a valid file extension"}
            end
          end
        end
      end

  """

  defmacro __using__(_) do
    quote do
      @behaviour UploadOld.Uploader

      defdelegate cast(uploadable), to: UploadOld
      defdelegate cast(uploadable, opts), to: UploadOld
      defdelegate cast_path(uploadable_path), to: UploadOld
      defdelegate cast_path(uploadable_path, opts), to: UploadOld
      defdelegate transfer(upload), to: UploadOld

      defoverridable cast: 1,
                     cast: 2,
                     cast_path: 1,
                     cast_path: 2,
                     transfer: 1
    end
  end

  @callback cast(UploadOld.uploadable()) :: {:ok, UploadOld.t()} | {:error, String.t()} | :error

  @callback cast(UploadOld.uploadable(), list) ::
              {:ok, UploadOld.t()} | {:error, String.t()} | :error

  @callback cast_path(UploadOld.uploadable_path()) ::
              {:ok, UploadOld.t()} | {:error, String.t()} | :error

  @callback cast_path(UploadOld.uploadable_path(), list) ::
              {:ok, UploadOld.t()} | {:error, String.t()} | :error

  @callback transfer(UploadOld.t()) :: {:ok, UploadOld.transferred()} | {:error, any}
end
