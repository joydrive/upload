defmodule Upload.RandomFileError do
  defexception [:reason]

  @impl true
  def message(%{reason: reason}) do
    "Failed to create temporary file: #{inspect(reason)}"
  end
end

defmodule Upload.DownloadError do
  defexception [:reason, :path, :key]

  @impl true
  def message(%{reason: reason, path: path, key: key}) do
    "Failed to download '#{key}' to '#{path}': #{inspect(reason)}"
  end
end
