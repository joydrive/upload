defmodule Upload.Test.Person do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  schema "people" do
    belongs_to(:avatar, Upload.Blob, on_replace: :delete, type: :binary_id)
  end

  def changeset(person, attrs \\ %{}) do
    cast(person, attrs, [])
  end
end
