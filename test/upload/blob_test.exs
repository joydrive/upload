defmodule Upload.BlobTest do
  use Upload.DataCase, async: true
  alias Upload.Blob

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
end
