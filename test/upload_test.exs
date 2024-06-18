defmodule UploadTest do
  use Upload.DataCase

  alias Upload.Test.Person
  alias Upload.Test.Repo

  import Ecto.Multi
  import Upload.Multi

  @path "test/fixtures/image.jpg"
  @upload %Plug.Upload{path: @path, filename: "image.jpg"}

  describe "create_variant/3" do
    test "create a single variant of an upload" do
      changeset = change_person(%{avatar: @upload})

      assert {:ok, %{person: person}} = upload_person(changeset)
      assert person.avatar

      {:ok, blob_variant} = Upload.create_variant(person.avatar, "small", &small_transform_avif/3)

      assert blob_variant.key == "uploads/users/avatars/123/variant/small.avif"
      assert blob_variant.key in list_uploaded_keys()
    end
  end

  describe "create_multiple_variants/3" do
    test "create a single variant of an upload" do
      changeset = change_person(%{avatar: @upload})

      assert {:ok, %{person: person}} = upload_person(changeset)
      assert person.avatar

      {:ok, [small_variant, small_avif_variant]} =
        Upload.create_multiple_variants(
          person.avatar,
          [
            "small",
            "small_avif"
          ],
          &transform_image/3
        )

      assert small_variant.key == "uploads/users/avatars/123/variant/small.jpg"
      assert small_variant.key in list_uploaded_keys()

      assert small_avif_variant.key == "uploads/users/avatars/123/variant/small_avif.avif"
      assert small_avif_variant.key in list_uploaded_keys()
    end
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

  defp transform_image(source, dest, "small") do
    with {:ok, image} <- Image.open(source),
         {:ok, image} <- Image.thumbnail(image, "768x480", crop: :center),
         {:ok, _} <- Image.write(image, dest <> ".jpg"),
         :ok <- File.cp(dest <> ".jpg", dest) do
      File.rm(dest <> ".jpg")
    end
  end

  defp transform_image(source, dest, "small_avif") do
    with {:ok, image} <- Image.open(source),
         {:ok, image} <- Image.thumbnail(image, "768x480", crop: :center),
         {:ok, _} <- Image.write(image, dest <> ".avif"),
         :ok <- File.cp(dest <> ".avif", dest) do
      File.rm(dest <> ".avif")
    end
  end

  defp small_transform_avif(source, dest, _), do: transform_image(source, dest, "small_avif")
end
