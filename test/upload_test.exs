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
      assert {:ok, person} = insert_person(%{avatar: @upload})
      assert person.avatar

      {:ok, [blob_variant]} =
        Upload.create_variant(person.avatar, "small", &small_transform_avif/3,
          formats: [:"image/avif"]
        )

      assert blob_variant.key == "uploads/users/123/avatar/small.avif"
      assert blob_variant.key in list_uploaded_keys()
    end

    test "works when called twice / handles the existing database items" do
      assert {:ok, person} = insert_person(%{avatar: @upload})
      assert person.avatar

      {:ok, [_blob_variant]} =
        Upload.create_variant(person.avatar, "small", &small_transform_avif/3,
          formats: [:"image/avif"]
        )

      person = Repo.reload(person) |> Repo.preload(:avatar)

      {:ok, [blob_variant]} =
        Upload.create_variant(person.avatar, "small", &small_transform_avif/3,
          formats: [:"image/avif"]
        )

      assert blob_variant.key == "uploads/users/123/avatar/small.avif"
      assert blob_variant.key in list_uploaded_keys()
    end

    test "replacing a single variant of an upload deletes the old one" do
      assert {:ok, person} = insert_person(%{avatar: @upload})
      assert person.avatar

      {:ok, [blob_variant1]} =
        Upload.create_variant(person.avatar, "small", &small_transform_avif/3,
          formats: [:"image/avif"]
        )

      assert blob_variant1.key in list_uploaded_keys()

      {:ok, [blob_variant2 | _]} =
        Upload.create_variant(person.avatar, "small", &small_transform_avif/3,
          formats: [:"image/avif"]
        )

      assert blob_variant2.key in list_uploaded_keys()
    end
  end

  describe "variant_exists?/2" do
    test "returns if a variant exists for a blob" do
      assert {:ok, person} = insert_person(%{avatar: @upload})

      refute Upload.variant_exists?(person.avatar, "small")

      {:ok, _} =
        Upload.create_variant(person.avatar, "small", &small_transform_avif/3,
          formats: [:"image/avif"]
        )

      assert Upload.variant_exists?(person.avatar, "small")
    end
  end

  describe "create_variants/3" do
    test "create a single variant of an upload" do
      assert {:ok, person} = insert_person(%{avatar: @upload})
      assert person.avatar

      {:ok, [small_variant, small_avif_variant]} =
        Upload.create_variants(
          person.avatar,
          [
            "small"
          ],
          &transform_image/3,
          formats: [:"image/jpeg", :"image/avif"]
        )

      assert small_variant.key in [
               "uploads/users/123/avatar/small.jpg",
               "uploads/users/123/avatar/small.avif"
             ]

      assert small_variant.key in list_uploaded_keys()

      assert small_variant.key in [
               "uploads/users/123/avatar/small.jpg",
               "uploads/users/123/avatar/small.avif"
             ]

      assert small_avif_variant.key in list_uploaded_keys()
    end

    test "works when called twice / handles the existing database items" do
      assert {:ok, person} = insert_person(%{avatar: @upload})
      assert person.avatar

      {:ok, [_small_variant, _small_avif_variant]} =
        Upload.create_variants(
          person.avatar,
          [
            "small"
          ],
          &transform_image/3,
          formats: [:"image/jpeg", :"image/avif"]
        )

      {:ok, [small_variant, small_avif_variant]} =
        Upload.create_variants(
          person.avatar,
          [
            "small"
          ],
          &transform_image/3,
          formats: [:"image/jpeg", :"image/avif"]
        )

      assert small_variant.key in [
               "uploads/users/123/avatar/small.jpg",
               "uploads/users/123/avatar/small.avif"
             ]

      assert small_variant.key in list_uploaded_keys()

      assert small_variant.key in [
               "uploads/users/123/avatar/small.jpg",
               "uploads/users/123/avatar/small.avif"
             ]

      assert small_avif_variant.key in list_uploaded_keys()
    end

    test "returns an error when a temp file cannot be created" do
      assert {:ok, person} = insert_person(%{avatar: @upload})
      assert person.avatar

      with_mock(Plug.Upload, random_file: fn _ -> {:error, :boom} end) do
        {:error, "download_and_insert_small_image/jpeg",
         %Upload.RandomFileError{reason: {:error, :boom}}} =
          Upload.create_variants(
            person.avatar,
            [
              "small"
            ],
            &transform_image/3
          )
      end
    end

    test "returns an error when the original file cannot be downloaded" do
      assert {:ok, person} = insert_person(%{avatar: @upload})
      assert person.avatar

      with_mock(Upload.Storage, download: fn _key, _ -> {:error, :boom} end) do
        {:error, "download_and_insert_small_image/jpeg",
         %Upload.DownloadError{reason: :boom, key: "uploads/users/123/avatar.jpg"}} =
          Upload.create_variants(
            person.avatar,
            [
              "small"
            ],
            &transform_image/3
          )
      end
    end

    test "returns an error when a temp file cannot be deleted" do
      assert {:ok, person} = insert_person(%{avatar: @upload})
      assert person.avatar

      with_mock(File, [:passthrough], rm: fn _path -> {:error, :enoent} end) do
        {:error, "download_and_insert_small_image/jpeg",
         %File.Error{reason: :enoent, action: "remove temporary file"}} =
          Upload.create_variants(
            person.avatar,
            [
              "small"
            ],
            &transform_image/3
          )
      end
    end

    test "returns an error when attempting to insert a bad key caused by a variant name" do
      assert {:ok, person} = insert_person(%{avatar: @upload})
      assert person.avatar

      {:error, "download_and_insert_._image/jpeg", changeset} =
        Upload.create_variants(
          person.avatar,
          [
            "."
          ],
          &transform_image/3
        )

      assert errors_on(changeset)[:key] == ["has invalid format"]
    end
  end

  describe "put_access_control_list/2" do
    test "can set the ACL for an uploaded blob" do
      assert {:ok, person} = insert_person(%{avatar: @upload})
      assert person.avatar

      :ok = Upload.put_access_control_list(person.avatar, "public_read")
    end
  end

  defp insert_person(attrs, opts \\ []) do
    key_function = Keyword.get(opts, :key_function, &key_function/1)

    changeset = Person.changeset(%Person{}, attrs)

    new()
    |> insert(:person, changeset)
    |> handle_changes(:upload_avatar, :person, changeset, :avatar, key_function: key_function)
    |> Repo.transaction()
    |> case do
      {:ok, %{person: person}} ->
        person = Repo.reload(person) |> Repo.preload(:avatar)
        {:ok, person}

      error ->
        error
    end
  end

  defp key_function(_changeset) do
    "uploads/users/123/avatar"
  end

  defp transform_image(source, variant, :"image/jpeg") do
    path = Path.join(System.tmp_dir!(), "#{variant}.jpg")

    with {:ok, image} <- Image.open(source),
         {:ok, image} <- Image.thumbnail(image, "768x480", crop: :center),
         {:ok, _} <- Image.write(image, path) do
      {:ok, path}
    end
  end

  defp transform_image(source, variant, :"image/avif") do
    path = Path.join(System.tmp_dir!(), "#{variant}.avif")

    with {:ok, image} <- Image.open(source),
         {:ok, image} <- Image.thumbnail(image, "768x480", crop: :center),
         {:ok, _} <- Image.write(image, path) do
      {:ok, path}
    end
  end

  defp small_transform_avif(source, _, _), do: transform_image(source, "small", :"image/avif")
end
