defmodule Upload.Stat.Image do
  @moduledoc false
  @behaviour Upload.Stat

  @impl true
  def stat(path, "image/" <> _), do: stat(path)
  def stat(_path, _content_type), do: {:ok, nil}

  @doc false
  def stat(path) do
    case Image.open(path) do
      {:ok, image} ->
        {:ok,
         %{
           width: Image.width(image),
           height: Image.height(image)
         }}

      {:error, _} ->
        {:ok, nil}
    end
  end
end
