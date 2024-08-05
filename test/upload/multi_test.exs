defmodule Upload.MultiTest do
  use Upload.DataCase

  alias Upload.Storage
  alias Upload.Test.Person
  alias Upload.Test.Repo

  import Ecto.Multi
  import Upload.Multi
  import Mock

  @path "test/fixtures/image.jpg"
  @upload %Plug.Upload{path: @path, filename: "image.jpg"}

  test "upload/3" do
    assert {:ok, %{person: person}} = insert_person(%{avatar: @upload})
    assert person.avatar_id

    assert person.avatar.key == "uploads/users/avatars/123.jpg"

    assert person.avatar
    assert person.avatar.key in list_uploaded_keys()
  end

  test "overwrites deletes old blobs" do
    {:ok, %{person: person, avatar: avatar}} = insert_person(%{avatar: @upload})

    assert person.avatar_id
    assert avatar.key == "uploads/users/avatars/123.jpg"

    with_mock(Storage, [:passthrough], delete: fn _key -> :ok end) do
      {:ok, person} = update_person(person, %{avatar: @upload})

      assert person.avatar
      assert person.avatar.key == "uploads/users/avatars/123.jpg"

      assert_called(Storage.delete("uploads/users/avatars/123.jpg"))
    end
  end

  describe "handle_changes/2" do
    test "handles overwriting existing images" do
      changeset =
        %Person{}
        |> Person.changeset(%{avatar: @upload})
        |> Upload.Changeset.cast_attachment(:avatar,
          key_function: fn _ -> "uploads/users/avatars/123" end
        )

      {:ok, %{insert: person}} =
        Ecto.Multi.new()
        |> Ecto.Multi.insert(:insert, changeset)
        |> Upload.Multi.handle_changes(changeset, [:avatar])
        |> Repo.transaction()

      key = person.avatar.key
      assert key in list_uploaded_keys()

      changeset =
        person
        |> Person.changeset(%{avatar: @upload})
        |> Upload.Changeset.cast_attachment(:avatar,
          key_function: fn _ -> "uploads/users/avatars/456" end
        )

      {:ok, %{update: person}} =
        Ecto.Multi.new()
        |> Ecto.Multi.update(:update, changeset)
        |> Upload.Multi.handle_changes(changeset, [:avatar])
        |> Repo.transaction()

      assert list_uploaded_keys() == [person.avatar.key]
    end

    test "can be used to insert and delete associated uploads" do
      changeset =
        %Person{}
        |> Person.changeset(%{avatar: @upload})
        |> Upload.Changeset.cast_attachment(:avatar,
          key_function: fn _ -> "uploads/users/avatars/123" end
        )

      {:ok, %{insert: person}} =
        Ecto.Multi.new()
        |> Ecto.Multi.insert(:insert, changeset)
        |> Upload.Multi.handle_changes(changeset, [:avatar])
        |> Repo.transaction()

      key = person.avatar.key
      assert key in list_uploaded_keys()

      {:ok, _} =
        Ecto.Multi.new()
        |> Upload.Multi.delete_blob(:delete_avatar, person.avatar)
        |> Ecto.Multi.delete(:delete, person)
        |> Repo.transaction()

      assert Repo.one(Person) == nil
      refute key in list_uploaded_keys()
    end

    test "can be used to insert and update associated uploads" do
      {:ok, %{person: person}} = insert_person(%{avatar: @upload})

      key = person.avatar.key
      assert key in list_uploaded_keys()

      {:ok, _} = update_person(person, %{avatar: nil})

      person = Repo.reload!(person) |> Repo.preload(:avatar)
      assert person.avatar == nil
      refute key in list_uploaded_keys()
    end

    test "cast_attachment/2 casting nil deletes the associated record and the remote file" do
      {:ok, %{person: person, avatar: avatar}} = insert_person(%{avatar: @upload})

      key = avatar.key
      assert key in list_uploaded_keys()

      update_person(person, %{avatar: nil})

      person = Repo.reload!(person) |> Repo.preload(:avatar)

      assert person.avatar == nil
      refute key in list_uploaded_keys()
    end
  end

  test "create a variant of an upload" do
    # changeset = update_person(%{avatar: @upload})
    # assert {:ok, %{person: person}} = insert_person(changeset)

    changeset =
      %Person{}
      |> Person.changeset(%{avatar: @upload})
      |> Upload.Changeset.cast_attachment(:avatar, key_function: &key_function/1)

    {:ok, %{avatar: avatar, avatar_small: [avatar_small]}} =
      new()
      |> insert(:person, changeset)
      |> upload(:avatar, fn ctx -> ctx.person.avatar end)
      |> upload_variant(
        :avatar_small,
        fn ctx -> ctx.person.avatar end,
        "small",
        &small_transform/3
      )
      |> Repo.transaction()

    assert avatar_small.key == "uploads/users/avatars/123/small.jpg"
    assert avatar_small.key in list_uploaded_keys()
    assert avatar_small.filename == "image_small.jpg"
    assert avatar_small.content_type == "image/jpeg"
    assert avatar_small.byte_size == 64_234
    assert avatar_small.checksum == "8ac7c07b446ac3986b77c2cf7b9754b1"
    assert avatar_small.metadata == %{width: 768, height: 480}
    assert avatar_small.variant == "small"
    assert avatar_small.original_blob_id == avatar.id
  end

  test "delete a variant of an upload" do
    assert {:ok, %{person: person}} = insert_person(%{avatar: @upload})

    assert person.avatar

    {:ok, [blob_variant]} = Upload.create_variant(person.avatar, "small", &small_transform/3)
    assert blob_variant.key in list_uploaded_keys()

    Upload.delete(blob_variant)

    refute blob_variant.key in list_uploaded_keys()
    assert person.avatar.key in list_uploaded_keys()
  end

  test "upload/3 when avatar is not provided" do
    assert {:ok, %{person: person}} = insert_person(%{})
    refute person.avatar_id
  end

  describe "upload/3" do
    # changeset = update_person(%{avatar: @upload})

    # assert {:ok, %{person: person}} = insert_person(changeset)
    # assert person.avatar.key in list_uploaded_keys()

    # assert {:ok, _} = delete_person(person)
    # refute person.avatar.key in list_uploaded_keys()
  end

  describe "purge/3" do
    test "removes the record from the file_store storage" do
      assert {:ok, %{person: person}} = insert_person(%{avatar: @upload})
      assert person.avatar.key in list_uploaded_keys()

      assert {:ok, _} = delete_person(person)
      refute person.avatar.key in list_uploaded_keys()
    end

    test "removes variants from the file_store storage" do
      assert {:ok, %{person: person}} = insert_person(%{avatar: @upload})

      {:ok, [blob_variant1]} =
        Upload.create_variant(person.avatar, "small1", &small_transform/3)

      assert blob_variant1.key == "uploads/users/avatars/123/small1.jpg"
      assert blob_variant1.key in list_uploaded_keys()

      {:ok, [blob_variant2]} =
        Upload.create_variant(person.avatar, "small2", &small_transform/3)

      assert blob_variant2.key == "uploads/users/avatars/123/small2.jpg"
      assert blob_variant2.key in list_uploaded_keys()

      assert {:ok, _} = delete_person(person)

      refute blob_variant1.key in list_uploaded_keys()
      refute blob_variant2.key in list_uploaded_keys()
    end

    test "does not fail when files are missing in the storage" do
      assert {:ok, %{person: person}} = insert_person(%{avatar: @upload})

      {:ok, [_blob_variant]} =
        Upload.create_variant(person.avatar, "small", &small_transform/3)

      :ok = Storage.delete_all()

      assert {:ok, _} = delete_person(person)
    end
  end

  defp delete_person(person) do
    new()
    |> delete(:person, person)
    |> delete_blob(:avatar, person.avatar)
    |> Repo.transaction()
  end

  defp insert_person(attrs) do
    changeset =
      %Person{}
      |> Person.changeset(attrs)
      |> Upload.Changeset.cast_attachment(:avatar, key_function: &key_function/1)

    new()
    |> insert(:person, changeset)
    |> upload(:avatar, fn ctx -> ctx.person.avatar end)
    |> Repo.transaction()
  end

  defp update_person(person, attrs) do
    changeset =
      person
      |> Person.changeset(attrs)
      |> Upload.Changeset.cast_attachment(:avatar, key_function: &key_function/1)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:person, changeset)
    |> Upload.Multi.handle_changes(changeset, [:avatar])
    |> Repo.transaction()
  end

  defp key_function(_changeset) do
    "uploads/users/avatars/123"
  end

  def small_transform(source, variant, format) do
    extension = format |> to_string() |> MIME.extensions() |> List.first()

    if !extension do
      raise "Could not determine extension for #{format}"
    end

    path = Path.join(System.tmp_dir!(), "#{variant}.#{extension}")

    with {:ok, image} <- Image.open(source),
         {:ok, image} <- Image.thumbnail(image, "768x480", crop: :center),
         {:ok, _} <- Image.write(image, path) do
      {:ok, path}
    end
  end
end
