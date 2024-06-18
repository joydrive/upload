defmodule Upload.Test.ErrorAdapter do
  @moduledoc false

  def upload(_store, _path, _key) do
    {:error, "boom"}
  end

  def delete(_store, _key) do
    {:error, "boom"}
  end
end
