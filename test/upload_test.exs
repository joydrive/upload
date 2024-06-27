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

    test "replacing a single variant of an upload deletes the old one" do
      changeset = change_person(%{avatar: @upload})

      assert {:ok, %{person: person}} = upload_person(changeset)
      assert person.avatar

      {:ok, blob_variant1} =
        Upload.create_variant(person.avatar, "small", &small_transform_avif/3)

      assert blob_variant1.key in list_uploaded_keys()

      {:ok, blob_variant2} =
        Upload.create_variant(person.avatar, "small", &small_transform_avif/3)

      assert blob_variant2.key in list_uploaded_keys()
    end
  end

  describe "variant_exists?/2" do
    test "returns if a variant exists for a blob" do
      changeset = change_person(%{avatar: @upload})

      assert {:ok, %{person: person}} = upload_person(changeset)

      refute Upload.variant_exists?(person.avatar, "small")

      {:ok, _} = Upload.create_variant(person.avatar, "small", &small_transform_avif/3)

      assert Upload.variant_exists?(person.avatar, "small")
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

    test "returns an error when a temp file cannot be created" do
      changeset = change_person(%{avatar: @upload})

      assert {:ok, %{person: person}} = upload_person(changeset)
      assert person.avatar

      with_mock(Plug.Upload, random_file: fn _ -> {:error, :boom} end) do
        {:error, "download_and_insert_small", %Upload.RandomFileError{reason: {:error, :boom}}} =
          Upload.create_multiple_variants(
            person.avatar,
            [
              "small"
            ],
            &transform_image/3
          )
      end
    end

    test "returns an error when the original file cannot be downloaded" do
      changeset = change_person(%{avatar: @upload})

      assert {:ok, %{person: person}} = upload_person(changeset)
      assert person.avatar

      with_mock(Upload.Storage, download: fn _key, _ -> {:error, :boom} end) do
        {:error, "download_and_insert_small",
         %Upload.DownloadError{reason: :boom, key: "uploads/users/avatars/123.jpg"}} =
          Upload.create_multiple_variants(
            person.avatar,
            [
              "small"
            ],
            &transform_image/3
          )
      end
    end

    test "returns an error when a temp file cannot be deleted" do
      changeset = change_person(%{avatar: @upload})

      assert {:ok, %{person: person}} = upload_person(changeset)
      assert person.avatar

      with_mock(File, [:passthrough], rm: fn _path -> {:error, :enoent} end) do
        {:error, "download_and_insert_small",
         %File.Error{reason: :enoent, action: "remove temporary file"}} =
          Upload.create_multiple_variants(
            person.avatar,
            [
              "small"
            ],
            fn _, _, _ -> :ok end
          )
      end
    end

    test "returns an error when attempting to insert a bad key caused by a variant name" do
      changeset = change_person(%{avatar: @upload})

      assert {:ok, %{person: person}} = upload_person(changeset)
      assert person.avatar

      {:error, "download_and_insert_.", changeset} =
        Upload.create_multiple_variants(
          person.avatar,
          [
            "."
          ],
          fn _, _, _ -> :ok end
        )

      assert errors_on(changeset)[:key] == ["has invalid format"]
    end
  end

  describe "put_access_control_list/2" do
    test "can set the ACL for an uploaded blob" do
      changeset = change_person(%{avatar: @upload})

      assert {:ok, %{person: person}} = upload_person(changeset)
      assert person.avatar

      :ok = Upload.put_access_control_list(person.avatar, "public_read")
    end
  end

  defp upload_person(changeset) do
    new()
    |> insert(:person, changeset)
    |> upload(:avatar, fn ctx -> ctx.person.avatar end)
    |> Repo.transaction()
  end

  defp change_person(attrs, opts \\ []) do
    key_function = Keyword.get(opts, :key_function, &key_function/1)

    %Person{}
    |> Person.changeset(attrs)
    |> Upload.Changeset.cast_attachment(:avatar, key_function: key_function)
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
