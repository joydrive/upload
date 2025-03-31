defmodule Upload.BlobTest do
  use Upload.DataCase, async: true

  alias Upload.Blob
  alias Upload.Test.Repo

  @attributes %{
    path: "test/fixtures/test.txt",
    key: "abcdef",
    filename: "text.txt",
    content_type: "text/plain",
    byte_size: 9,
    checksum: "blah"
  }

  @errors %{
    byte_size: ["can't be blank"],
    checksum: ["can't be blank"],
    key: ["can't be blank"],
    content_type: ["can't be blank"],
    filename: ["can't be blank"]
  }

  test "is valid with required attributes" do
    changeset = Blob.changeset(%Blob{}, @attributes)
    assert changeset.valid?
    assert changeset.errors == []
  end

  test "is invalid when missing required attributes" do
    changeset = Blob.changeset(%Blob{}, %{})
    assert errors_on(changeset) == @errors
  end

  test "adds the file extension to the key from the MIME type" do
    blob = Blob.changeset(%Blob{}, @attributes)

    assert blob.changes.key == "abcdef.txt"
  end

  test "allows the avif MIME type" do
    changeset = Blob.changeset(%Blob{}, @attributes |> Map.put(:content_type, "image/avif"))

    assert changeset.valid?
  end

  test "allows the webp MIME type" do
    changeset = Blob.changeset(%Blob{}, @attributes |> Map.put(:content_type, "image/webp"))

    assert changeset.valid?
  end

  test "returns an error when the file extension can not be determined from the MIME type" do
    changeset = Blob.changeset(%Blob{}, @attributes |> Map.put(:content_type, "not-a-real-mime"))

    refute changeset.valid?

    assert errors_on(changeset) == %{
             key: ["Could not set the extension from the given MIME type: 'not-a-real-mime'"]
           }
  end

  test "does not allow keys with periods / existing extensions" do
    changeset = Blob.changeset(%Blob{}, @attributes |> Map.put(:key, "foo.jpg"))
    refute changeset.valid?

    changeset = Blob.changeset(%Blob{}, @attributes |> Map.put(:key, "."))
    refute changeset.valid?
  end

  test "does not allow setting the original_blob_id to a variant blob" do
    blob = Repo.insert!(Blob.changeset(%Blob{}, @attributes))

    variant_blob =
      Repo.insert!(
        Blob.changeset(
          %Blob{},
          @attributes
          |> Map.merge(%{
            key: "xyz",
            variant: "foo",
            original_blob_id: blob.id
          })
        )
      )

    changeset =
      Blob.changeset(
        %Blob{},
        @attributes
        |> Map.merge(%{
          variant: "foo2",
          original_blob_id: variant_blob.id
        })
      )

    assert errors_on(changeset) == %{
             original_blob_id: ["Can not set original_blob_id to a variant blob."]
           }
  end
end
