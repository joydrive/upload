defmodule Upload.Test.Person do
  use Ecto.Schema

  import Ecto.Changeset
  import Upload.Changeset

  schema "people" do
    belongs_to(:avatar, Upload.Blob)
  end

  def changeset(person, attrs \\ %{}) do
    person
    |> cast(attrs, [])
    |> cast_upload(:avatar)
  end
end