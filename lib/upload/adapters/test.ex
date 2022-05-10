defmodule Upload.Adapters.Test do
  use Upload.Adapter

  alias Upload.Adapters.Test.Server

  @moduledoc """
  An `Upload.Adapter` that keeps track of uploaded files in memory, so that
  you can make assertions.

  ### Setup

  Add the following to `test_helper.exs`.

  ```elixir
  Upload.Adapters.Test.start()
  ```

  ### Example

  Then you can use the Upload adapter in tests.

  ```elixir
  test "files are uploaded" do
    assert {:ok, upload} = Upload.cast_path("/path/to/file.txt")
    assert {:ok, upload} = Upload.transfer(upload)
    assert map_size(Upload.Adapters.Test.get_uploads()) == 1
  end
  ```
  """

  def start() do
    Server.start_link(nil)
  end

  def child_spec(_) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []}
    }
  end

  @doc """
  Get all uploads.
  """
  def get_uploads do
    Server.get_uploads(self())
  end

  @doc """
  Add an upload to the state.
  """
  def put_upload(upload) do
    Server.put_upload(self(), upload.key, upload)
  end

  @doc """
  Removes an upload from the state.
  """
  def delete_upload(key) do
    Server.delete_upload(self(), key)
  end

  @impl true
  def get_url(key), do: key

  @impl true
  def get_signed_url(key, _opts), do: {:ok, get_url(key)}

  @impl true
  def transfer(%Upload{} = upload) do
    upload = %Upload{upload | status: :transferred}
    put_upload(upload)
    {:ok, upload}
  end

  @impl true
  def delete(key) do
    delete_upload(key)
    :ok
  end
end
