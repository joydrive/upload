defmodule UploadTest do
  use ExUnit.Case

  alias Upload.Test.Repo

  defmodule Person do
    use Ecto.Schema
    import Ecto.Changeset
    import Upload

    schema "people" do
      embeds_one :avatar, Person.Avatar
    end

    def changeset(person, attrs \\ %{}) do
      person
      |> cast(attrs, [])
      |> cast_upload(:avatar)
    end
  end

  defmodule Person.Avatar do
    use Upload
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  test "saves a file" do
    assert {:ok, _} = start_supervised(FileStore.Adapters.Test)
    changeset = Person.changeset(%Person{}, %{avatar: %{key: "foo"}})

    assert {:ok, person} = Repo.insert(changeset)
    assert person.avatar.key == "foo"
  end
end
