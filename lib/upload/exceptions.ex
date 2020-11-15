defmodule Upload.ExitError do
  defexception [:cmd, :status]

  @impl true
  def message(%{cmd: cmd, status: status}) do
    "Command `#{inspect(cmd)}` returned a non-zero exit status: #{inspect(status)}"
  end
end

defmodule Upload.CommandError do
  defexception [:cmd, :reason]

  @impl true
  def message(%{cmd: cmd, reason: :enoent}) do
    "Command `#{inspect(cmd)}` is not installed"
  end

  def message(%{cmd: cmd, reason: reason}) do
    reason =
      reason
      |> :file.format_error()
      |> IO.chardata_to_string()

    "Command `#{inspect(cmd)}` failed: #{reason}"
  end
end

defmodule Upload.DownloadError do
  defexception [:key, :path, :reason]

  @impl true
  def message(%{key: key, path: path, reason: reason}) do
    "Failed to download #{inspect(key)} to #{inspect(path)}: #{inspect(reason)}"
  end
end

defmodule Upload.UploadError do
  defexception [:key, :path, :reason]

  @impl true
  def message(%{key: key, path: path, reason: reason}) do
    "Failed to upload #{inspect(path)} to #{inspect(key)}: #{inspect(reason)}"
  end
end

defmodule Upload.RandomFileError do
  defexception [:reason]

  @impl true
  def message(%{reason: reason}) do
    "Failed to create temporary file: #{inspect(reason)}"
  end
end
