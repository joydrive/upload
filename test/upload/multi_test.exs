defmodule Upload.MultiTest do
  use Upload.DataCase

  alias Upload.Test.Repo
  alias Upload.Test.Person

  import Ecto.Multi
  import Upload.Multi

  @path "test/fixtures/image.jpg"
  @upload %Plug.Upload{path: @path, filename: "image.jpg"}

  test "upload/3" do
    changeset = change_person(%{avatar: @upload})
    assert {:ok, %{person: person}} = upload_person(changeset)
    assert person.avatar_id

    assert person.avatar.key == "uploads/users/avatars/123.jpg"

    assert person.avatar
    assert person.avatar.key in list_uploaded_keys()
  end

  test "create a variant of an upload" do
    changeset = change_person(%{avatar: @upload})
    assert {:ok, %{person: person}} = upload_person(changeset)

    assert person.avatar

    {:ok, blob_variant} = Upload.create_variant(person.avatar, "small", &small_transform_avif/3)

    assert blob_variant.key == "uploads/users/avatars/123/variant/small.avif"
    assert blob_variant.key in list_uploaded_keys()
    assert blob_variant.filename == "image_small.jpg"
    assert blob_variant.content_type == "image/avif"
    assert blob_variant.byte_size == 32_696
    assert blob_variant.checksum == "097b6074636203fc2866a8118949f286"
    assert blob_variant.metadata == %{width: 768, height: 480}
    assert blob_variant.variant == "small"
    assert blob_variant.original_blob_id == person.avatar.id
  end

  test "upload/3 when avatar is not provided" do
    changeset = change_person(%{})
    assert {:ok, %{person: person}} = upload_person(changeset)
    refute person.avatar_id
  end

  describe "purge/3" do
    test "removes the record from the file_store storage" do
      changeset = change_person(%{avatar: @upload})

      assert {:ok, %{person: person}} = upload_person(changeset)
      assert person.avatar.key in list_uploaded_keys()

      assert {:ok, _} = purge_person(person)
      refute person.avatar.key in list_uploaded_keys()
    end

    test "removes variants from the file_store storage" do
      changeset = change_person(%{avatar: @upload})

      assert {:ok, %{person: person}} = upload_person(changeset)

      {:ok, blob_variant} = Upload.create_variant(person.avatar, "small", &small_transform_avif/3)
      assert blob_variant.key == "uploads/users/avatars/123/variant/small.avif"
      assert blob_variant.key in list_uploaded_keys()

      assert {:ok, _} = purge_person(person)

      refute blob_variant.key in list_uploaded_keys()
    end
  end

  defp purge_person(person) do
    new()
    |> delete(:person, person)
    |> purge(:avatar, person.avatar)
    |> Repo.transaction()
  end

  defp upload_person(changeset) do
    new()
    |> insert(:person, changeset)
    |> upload(:avatar, fn ctx -> ctx.person.avatar end)
    |> Repo.transaction()
  end

  defp change_person(attrs) do
    %Person{}
    |> Person.changeset(attrs)
    |> Upload.Changeset.cast_attachment(:avatar, key_function: &key_function/1)
  end

  defp key_function(_changeset) do
    "uploads/users/avatars/123"
  end

  defp small_transform_avif(source, dest, _variant) do
    with {:ok, image} <- Image.open(source),
         {:ok, image} <- Image.thumbnail(image, "768x480", crop: :center),
         {:ok, _} <- Image.write(image, dest <> ".avif"),
         :ok <- File.cp(dest <> ".avif", dest) do
          File.rm(dest <> ".avif")
    end
  end
end
