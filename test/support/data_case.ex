defmodule Upload.DataCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Upload.Test.Repo
  alias FileStore.Adapters.Memory
  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      import Upload.DataCase
    end
  end

  setup do
    set_adapter(Memory)
    :ok = Sandbox.checkout(Repo)
    {:ok, _} = start_supervised(Memory)
    :ok
  end

  def set_adapter(adapter) do
    Application.put_env(:upload, Upload.Storage, adapter: adapter, base_url: "http://example.com")
  end

  def list_uploaded_keys do
    Enum.to_list(Upload.Storage.list!())
  end

  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
