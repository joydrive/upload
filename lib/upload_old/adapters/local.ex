defmodule UploadOld.Adapters.Local do
  @moduledoc """
  An `UploadOld.Adapter` that saves files to disk.

  ### Configuration

      config :upload, UploadOld.Adapters.Local,
        base_url: "/uploads", # optional
        storage_path: "priv/static/uploads" # optional

  """

  use UploadOld.Adapter
  alias UploadOld.Config

  @doc """
  Path where files are stored. Defaults to `priv/static/uploads`.

  ## Examples

      iex> UploadOld.Adapters.Local.storage_path()
      "priv/static/uploads"

  """
  def storage_path do
    Config.get(__MODULE__, :storage_path, "priv/static/uploads")
  end

  @doc """
  The URL prefix for the file key.

  ## Examples

      iex> UploadOld.Adapters.Local.base_url()
      "/uploads"

  """
  def base_url do
    Config.get(__MODULE__, :base_url, "/uploads")
  end

  @impl true
  def get_url(key), do: join_url(base_url(), key)

  @impl true
  def get_signed_url(key, _opts), do: {:ok, get_url(key)}

  @impl true
  def transfer(%UploadOld{key: key, path: path} = upload) do
    filename = Path.join(storage_path(), key)
    directory = Path.dirname(filename)

    with :ok <- File.mkdir_p(directory),
         :ok <- File.cp(path, filename) do
      {:ok, %UploadOld{upload | status: :transferred}}
    else
      _ ->
        {:error, "failed to transfer file"}
    end
  end

  @impl true
  def delete(key) do
    filename = Path.join(storage_path(), key)

    case File.rm(filename) do
      :ok -> :ok
      {:error, posix_error} -> {:error, inspect(posix_error)}
    end
  end

  defp join_url(a, b) do
    String.trim_trailing(a, "/") <> "/" <> String.trim_leading(b, "/")
  end
end
