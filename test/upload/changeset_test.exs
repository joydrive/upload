defmodule Upload.ChangesetTest do
  use Upload.DataCase

  import Upload.Changeset

  alias Upload.Test.Person

  @path "test/fixtures/image.jpg"
  @upload %Plug.Upload{
    path: @path,
    filename: "image.jpg",
    content_type: "image/jpeg"
  }

  describe "cast_attachment/3" do
    @invalid {"is invalid", validation: :assoc, type: :map}
    @invalid_custom {"boom", validation: :assoc, type: :map}

    @required {"can't be blank", validation: :required}
    @required_custom {"boom", validation: :required}

    test "accepts a Plug.Upload" do
      changeset = change_person(%{avatar: @upload})

      assert changeset.valid?
      assert changeset.changes.avatar
      assert changeset.changes.avatar.action == :insert
      assert changeset.changes.avatar.changes.key
      assert changeset.changes.avatar.changes.path
      assert changeset.changes.avatar.changes.filename
    end

    test "rejects invalid values" do
      changeset = change_person(%{avatar: @path})
      refute changeset.valid?
      assert changeset.errors[:avatar] == @invalid
    end

    test "rejects invalid values with a custom message" do
      changeset = change_person(%{avatar: 42}, invalid_message: "boom")
      refute changeset.valid?
      assert changeset.errors[:avatar] == @invalid_custom
    end

    test "accepts nil" do
      changeset = change_person(%{avatar: nil})
      assert changeset.valid?
      assert changeset.changes.avatar == nil
    end

    test "rejects `nil` when required" do
      changeset = change_person(%{avatar: nil}, required: true)
      refute changeset.valid?
      assert changeset.errors[:avatar] == @required
    end

    test "rejects `nil` when a custom message when required" do
      changeset = change_person(%{avatar: nil}, required: true, required_message: "boom")
      refute changeset.valid?
      assert changeset.errors[:avatar] == @required_custom
    end
  end

  describe "validate_attachment_type/4" do
    test "can allow only specific attachment types" do
      upload = %Plug.Upload{
        path: @path,
        filename: "test/fixtures/is_actually_a_jpg.binary",
        content_type: "user-value-here"
      }

      changeset =
        %{avatar: upload}
        |> change_person(required: true)
        |> validate_attachment_type(:avatar, allow: ["image/jpeg"])

      assert changeset.valid?

      changeset =
        %{avatar: upload}
        |> change_person(required: true)
        |> validate_attachment_type(:avatar, allow: ["image/png"])

      refute changeset.valid?

      assert changeset.errors ==
               [avatar: {"is not a supported file type", [allowed: ["image/png"]]}]
    end

    @tag :pending
    test "forbid"

    @tag :pending
    test "accepts a custom message"
  end

  describe "validate_attachment_size/3" do
    @tag :pending
    test "less than"

    @tag :pending
    test "greater than"

    @tag :pending
    test "accepts a custom message"
  end

  defp change_person(attrs, opts \\ []) do
    %Person{}
    |> Person.changeset(attrs)
    |> cast_attachment(:avatar, opts ++ [key_function: &key_function/1])
  end

  defp key_function(_changeset) do
    "uploads/users/avatars/123"
  end
end
