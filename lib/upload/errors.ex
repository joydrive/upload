defmodule Upload.RandomFileError do
  defexception [:reason]

  @impl true
  def message(%{reason: reason}) do
    "Failed to create temporary file: #{inspect(reason)}"
  end
end
