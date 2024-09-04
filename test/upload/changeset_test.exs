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
      changeset = update_person(%{avatar: @upload})

      assert changeset.valid?
      assert changeset.changes.avatar
      assert changeset.changes.avatar.action == :insert
      assert changeset.changes.avatar.changes.key
      assert changeset.changes.avatar.changes.path
      assert changeset.changes.avatar.changes.filename
    end

    test "accepts a file path" do
      changeset = update_person(%{avatar: "test/fixtures/image.jpg"})

      assert changeset.valid?
    end

    test "rejects invalid values" do
      changeset = update_person(%{avatar: "foo"})
      refute changeset.valid?
      assert changeset.errors[:avatar] == @invalid
    end

    test "rejects invalid values with a custom message" do
      changeset = update_person(%{avatar: 42}, invalid_message: "boom")
      refute changeset.valid?
      assert changeset.errors[:avatar] == @invalid_custom
    end

    test "accepts nil" do
      changeset = update_person(%{avatar: nil})

      assert changeset.valid?
    end

    test "rejects `nil` when required" do
      changeset = update_person(%{avatar: nil}, required: true)
      refute changeset.valid?
      assert changeset.errors[:avatar] == @required
    end

    test "rejects `nil` when a custom message when required" do
      changeset = update_person(%{avatar: nil}, required: true, required_message: "boom")
      refute changeset.valid?
      assert changeset.errors[:avatar] == @required_custom
    end

    test "raises when the key_function option is not a function" do
      assert_raise(ArgumentError, fn ->
        update_person(%{avatar: nil}, key_function: :foo)
      end)
    end
  end

  describe "validate_attchment/4" do
    test "does nothing when there is no change" do
      changeset =
        %{avatar: @upload}
        |> update_person()
        |> validate_attachment(:avatar, :variant, fn _ -> :ok end)

      assert changeset.valid?
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
        |> update_person(required: true)
        |> validate_attachment_type(:avatar, allow: ["image/jpeg"])

      assert changeset.valid?

      changeset =
        %{avatar: upload}
        |> update_person(required: true)
        |> validate_attachment_type(:avatar, allow: ["image/png"])

      refute changeset.valid?

      assert changeset.errors ==
               [avatar: {"is not a supported file type", [allowed: ["image/png"]]}]
    end
  end

  describe "validate_attachment_size/3" do
    test "fails the image is larger than the specified maximum size" do
      changeset =
        %{avatar: @upload}
        |> update_person(required: true)
        |> validate_attachment_size(:avatar, smaller_than: {1, :megabyte})

      refute changeset.valid?
      assert errors_on(changeset) == %{avatar: ["must be smaller than 1 megabyte(s)"]}
    end

    test "succeeds when the image is smaller than the specified maximum size" do
      changeset =
        %{avatar: @upload}
        |> update_person(required: true)
        |> validate_attachment_size(:avatar, smaller_than: {2, :megabyte})

      assert changeset.valid?
    end
  end

  defp update_person(attrs, opts \\ []) do
    %Person{}
    |> Person.changeset(attrs)
    |> cast_attachment(:avatar, opts ++ [key_function: &key_function/1])
  end

  defp key_function(_changeset) do
    "uploads/users/123/avatar"
  end
end
