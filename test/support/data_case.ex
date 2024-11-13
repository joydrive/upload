defmodule Upload.DataCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias FileStore.Adapters.Memory
  alias Upload.Test.Repo

  using do
    quote do
      use Upload.Testing

      import Upload.DataCase
      import Mock
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

  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
