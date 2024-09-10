defmodule UploadOld.Adapter do
  @moduledoc """
  A behaviour that specifies how an adapter should work.
  """

  defmacro __using__(_) do
    quote do
      @behaviour UploadOld.Adapter
    end
  end

  @callback get_url(String.t()) :: String.t()
  @callback get_signed_url(String.t(), Keyword.t()) :: {:ok, String.t()} | {:error, String.t()}
  @callback transfer(UploadOld.t()) :: {:ok, UploadOld.transferred()} | {:error, String.t()}
  @callback delete(String.t()) :: :ok | {:error, String.t()}
end
