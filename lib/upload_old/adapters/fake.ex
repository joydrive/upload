defmodule UploadOld.Adapters.Fake do
  @moduledoc """
  An `UploadOld.Adapter` that doesn't actually store files.
  """

  use UploadOld.Adapter

  @impl true
  def get_url(key) do
    key
  end

  @impl true
  def get_signed_url(key, _opts), do: {:ok, get_url(key)}

  @impl true
  def transfer(%UploadOld{} = upload) do
    {:ok, %UploadOld{upload | status: :transferred}}
  end

  @impl true
  def delete(_key) do
    :ok
  end
end
