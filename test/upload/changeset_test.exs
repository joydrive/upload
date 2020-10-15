defmodule Upload.ChangesetTest do
  use Upload.DataCase

  import Upload.Changeset

  alias Upload.Test.Person

  @path fixture_path("test.txt")
  @upload %Plug.Upload{filename: "test.txt", path: @path}

  describe "cast_attachment/2" do
    test "accepts a Plug.Upload" do
      changeset = change_person(%{avatar: @upload})
      assert changeset.valid?
      assert changeset.changes.avatar
      assert changeset.changes.avatar.action == :insert
      assert changeset.changes.avatar.changes.key
      assert changeset.changes.avatar.changes.path
      assert changeset.changes.avatar.changes.filename
    end

    test "accepts nil" do
      changeset = change_person(%{avatar: nil})
      assert changeset.valid?
      assert changeset.changes.avatar == nil
    end

    test "rejects a path" do
      changeset = change_person(%{avatar: @path})
      refute changeset.valid?
      assert changeset.errors == [{:avatar, {"is invalid", []}}]
    end

    test "rejects invalid values with a custom message" do
      changeset = change_person(%{avatar: 42}, invalid_message: "boom")
      refute changeset.valid?
      assert changeset.errors == [{:avatar, {"boom", []}}]
    end
  end

  describe "validate_content_type/4" do
    test "accepts included types" do
      changeset = change_content_type("text/plain")
      assert changeset.valid?
    end

    test "rejects excluded types" do
      changeset = change_content_type("image/png")
      refute changeset.valid?
      assert errors_on(changeset) == %{avatar: %{content_type: ["is invalid"]}}
    end
  end

  defp change_content_type(type) do
    %{avatar: %Plug.Upload{@upload | content_type: type}}
    |> change_person()
    |> validate_content_type(:avatar, ["text/plain"])
  end

  defp change_person(attrs, opts \\ []) do
    %Person{}
    |> Person.changeset(attrs)
    |> cast_attachment(:avatar, opts)
  end
end
