defmodule Upload.MultiTest do
  use Upload.DataCase

  alias Upload.Storage
  alias Upload.Test.Person
  alias Upload.Test.Repo

  import Ecto.Multi
  import ExUnit.CaptureLog
  import Mock
  import Upload.Multi

  require Logger

  @path "test/fixtures/image.jpg"
  @upload %Plug.Upload{path: @path, filename: "image.jpg"}

  describe "handle_changes" do
    test "will validate changes" do
      changeset = Person.changeset(%Person{}, %{avatar: "test/fixtures/test.txt"})

      {:error, _, changeset, _} =
        Ecto.Multi.new()
        |> Ecto.Multi.insert(:insert_person, changeset)
        |> Upload.Multi.handle_changes(:upload_avatar, :insert_person, changeset, :avatar,
          key_function: &key_function/1,
          validate: fn changeset, field ->
            Upload.Changeset.validate_attachment_type(changeset, field, allow: ["image/jpeg"])
          end
        )
        |> Repo.transaction()

      assert errors_on(changeset)[:avatar] == ["is not a supported file type"]
    end

    test "works when provided a changeset with nil changes" do
      changeset = %{Person.changeset(%Person{}) | params: nil}

      {:ok, _} =
        Ecto.Multi.new()
        |> Ecto.Multi.insert(:insert_person, changeset)
        |> Upload.Multi.handle_changes(:upload_avatar, :insert_person, changeset, :avatar,
          key_function: &key_function/1
        )
        |> Repo.transaction()
    end

    test "does nothing when provided a changeset with empty changes for a record with an existing upload" do
      changeset = Person.changeset(%Person{}, %{avatar: @upload})

      {:ok, _} =
        Ecto.Multi.new()
        |> Ecto.Multi.insert(:person, changeset)
        |> Upload.Multi.handle_changes(:upload_avatar, :person, changeset, :avatar,
          key_function: &key_function/1
        )
        |> Upload.Multi.create_variant(
          fn ctx -> ctx.upload_avatar.avatar end,
          :small,
          &small_transform/3
        )
        |> Repo.transaction()

      person = Repo.one(Person) |> Repo.preload(:avatar)
      assert person.avatar

      changeset = Person.changeset(person, %{})

      {:ok, _} =
        Ecto.Multi.new()
        |> Ecto.Multi.update(:update_person, changeset)
        |> Upload.Multi.handle_changes(:upload_avatar, :update_person, changeset, :avatar,
          key_function: &key_function/1
        )
        |> Repo.transaction()

      person = Repo.one(Person) |> Repo.preload(:avatar)
      assert person.avatar
    end
  end

  describe "create_variant" do
    test "will create a variant" do
      changeset = Person.changeset(%Person{}, %{avatar: @upload})

      {:ok, _} =
        Ecto.Multi.new()
        |> Ecto.Multi.insert(:person, changeset)
        |> Upload.Multi.handle_changes(:upload_avatar, :person, changeset, :avatar,
          key_function: &key_function/1
        )
        |> Upload.Multi.create_variant(
          fn ctx -> ctx.upload_avatar.avatar end,
          :small,
          &small_transform/3
        )
        |> Repo.transaction()

      person = Repo.one(Person) |> Repo.preload(avatar: :variants)

      variant = List.first(person.avatar.variants)

      assert variant.variant == "small"
    end

    test "handles when there are no changes" do
      changeset = Person.changeset(%Person{}, %{})

      {:ok, _} =
        Ecto.Multi.new()
        |> Ecto.Multi.insert(:person, changeset)
        |> Upload.Multi.handle_changes(:upload_avatar, :person, changeset, :avatar,
          key_function: &key_function/1
        )
        |> Upload.Multi.create_variant(
          fn ctx -> ctx.upload_avatar.avatar end,
          :small,
          &small_transform/3
        )
        |> Repo.transaction()
    end
  end

  test "upload/3" do
    assert {:ok, person} = insert_person(%{avatar: @upload})
    assert person.avatar_id

    assert person.avatar.key == "uploads/users/#{person.id}/avatar.jpg"

    assert person.avatar
    assert person.avatar.key in list_uploaded_keys()
  end

  test "invokes the on_upload callback" do
    logs =
      capture_log(fn ->
        {:ok, _} = insert_person(%{avatar: @upload})
      end)

    assert logs =~ "on_upload called"
  end

  test "sets the ACL to public" do
    assert {:ok, person} = insert_person(%{avatar: @upload})
    assert person.avatar_id

    with_mock(Storage, [:passthrough], put_access_control_list: fn _key, _acl -> :ok end) do
      {:ok, person} = update_person(person, %{avatar: @upload})

      assert person.avatar
      assert person.avatar.key == "uploads/users/#{person.id}/avatar.jpg"

      assert_called(
        Storage.put_access_control_list("uploads/users/#{person.id}/avatar.jpg", acl: :public)
      )
    end
  end

  test "overwrites and deletes old blobs" do
    {:ok, person} = insert_person(%{avatar: @upload})

    assert person.avatar_id
    assert person.avatar.key == "uploads/users/#{person.id}/avatar.jpg"

    with_mock(Storage, [:passthrough], delete: fn _key -> :ok end) do
      {:ok, person} = update_person(person, %{avatar: @upload})

      assert person.avatar
      assert person.avatar.key == "uploads/users/#{person.id}/avatar.jpg"

      assert_called(Storage.delete("uploads/users/#{person.id}/avatar.jpg"))
    end
  end

  describe "handle_changes/6" do
    test "can use the ID in the upload key from a record created from the multi itself" do
      changeset =
        %Person{}
        |> Person.changeset(%{avatar: @upload})

      {:ok, %{person: person}} =
        Ecto.Multi.new()
        |> Ecto.Multi.insert(:insert_person, changeset)
        |> Upload.Multi.handle_changes(:person, :insert_person, changeset, :avatar,
          key_function: fn user ->
            "uploads/users/#{user.id}/avatar"
          end
        )
        |> Repo.transaction()

      assert person.avatar.key == "uploads/users/#{person.id}/avatar.jpg"
    end

    test "handles overwriting existing images" do
      {:ok, person} = insert_person(%{avatar: @upload})

      key = person.avatar.key
      assert key in list_uploaded_keys()

      changeset = Person.changeset(person, %{avatar: @upload})

      {:ok, %{update: person}} =
        Ecto.Multi.new()
        |> Ecto.Multi.update(:update, changeset)
        |> Upload.Multi.handle_changes(:upload, :update, changeset, :avatar,
          key_function: fn user ->
            "uploads/users/#{user.id}/avatar"
          end
        )
        |> Repo.transaction()

      assert list_uploaded_keys() == [person.avatar.key]
    end

    test "can be used to insert and delete associated uploads" do
      changeset = Person.changeset(%Person{}, %{avatar: @upload})

      {:ok, %{insert: person}} =
        Ecto.Multi.new()
        |> Ecto.Multi.insert(:insert, changeset)
        |> Upload.Multi.handle_changes(:upload, :insert, changeset, :avatar,
          key_function: fn user ->
            "uploads/users/#{user.id}/avatar"
          end
        )
        |> Repo.transaction()

      person = person |> Repo.reload() |> Repo.preload(:avatar)

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

    test "passing nil deletes the associated record and the remote file" do
      {:ok, person} = insert_person(%{avatar: @upload})

      key = person.avatar.key
      assert key in list_uploaded_keys()

      update_person(person, %{avatar: nil})

      person = Repo.reload!(person) |> Repo.preload(:avatar)

      assert person.avatar == nil
      refute key in list_uploaded_keys()
    end

    test "uploads successfully when there is an existing blob with the same key that is disassociated" do
      {:ok, person} = insert_person(%{avatar: @upload})

      assert person.avatar != nil
      assert person.avatar.key == "uploads/users/#{person.id}/avatar.jpg"

      {:ok, _} = update_person(person, %{avatar_id: nil})
      person = person |> Repo.reload() |> Repo.preload(:avatar)
      assert person.avatar == nil
      assert person.avatar_id == nil

      # Ensure the blob record still exists and is orphaned.
      assert Repo.aggregate(Upload.Blob, :count) == 1

      {:ok, _} = update_person(person, %{avatar: @upload})
      person = person |> Repo.reload() |> Repo.preload(:avatar)
      assert person.avatar != nil
      assert person.avatar.key == "uploads/users/#{person.id}/avatar.jpg"

      # Ensure only blob record exists.
      assert Repo.aggregate(Upload.Blob, :count) == 1
    end
  end

  test "create a variant of an upload" do
    {:ok, person} = insert_person(%{avatar: @upload})

    {:ok, %{avatar_small: [avatar_small]}} =
      new()
      |> put(:person, person)
      |> upload_variant(
        :avatar_small,
        fn ctx -> ctx.person.avatar end,
        "small",
        &small_transform/3
      )
      |> Repo.transaction()

    assert avatar_small.key == "uploads/users/#{person.id}/avatar/small.jpg"
    assert avatar_small.key in list_uploaded_keys()
    assert avatar_small.filename == "image_small.jpg"
    assert avatar_small.content_type == "image/jpeg"
    assert avatar_small.byte_size == 64_234
    assert avatar_small.checksum == "8ac7c07b446ac3986b77c2cf7b9754b1"
    assert avatar_small.metadata == %{width: 768, height: 480}
    assert avatar_small.variant == "small"
    assert avatar_small.original_blob_id == person.avatar.id
  end

  test "delete a variant of an upload" do
    assert {:ok, person} = insert_person(%{avatar: @upload})

    assert person.avatar

    {:ok, [blob_variant]} = Upload.create_variant(person.avatar, "small", &small_transform/3)
    assert blob_variant.key in list_uploaded_keys()

    Upload.delete(blob_variant)

    refute blob_variant.key in list_uploaded_keys()
    assert person.avatar.key in list_uploaded_keys()
  end

  test "upload/3 when avatar is not provided" do
    assert {:ok, person} = insert_person(%{})
    refute person.avatar_id
  end

  describe "purge/3" do
    test "removes the record from the file_store storage" do
      assert {:ok, person} = insert_person(%{avatar: @upload})
      assert person.avatar.key in list_uploaded_keys()

      assert {:ok, _} = delete_person(person)
      refute person.avatar.key in list_uploaded_keys()
    end

    test "removes variants from the file_store storage" do
      assert {:ok, person} = insert_person(%{avatar: @upload})

      {:ok, [blob_variant1]} =
        Upload.create_variant(person.avatar, "small1", &small_transform/3)

      assert blob_variant1.key == "uploads/users/#{person.id}/avatar/small1.jpg"
      assert blob_variant1.key in list_uploaded_keys()

      {:ok, [blob_variant2]} =
        Upload.create_variant(person.avatar, "small2", &small_transform/3)

      assert blob_variant2.key == "uploads/users/#{person.id}/avatar/small2.jpg"
      assert blob_variant2.key in list_uploaded_keys()

      assert {:ok, _} = delete_person(person)

      refute blob_variant1.key in list_uploaded_keys()
      refute blob_variant2.key in list_uploaded_keys()
    end

    test "does not fail when files are missing in the storage" do
      assert {:ok, person} = insert_person(%{avatar: @upload})

      {:ok, [_blob_variant]} =
        Upload.create_variant(person.avatar, "small", &small_transform/3)

      :ok = Storage.delete_all()

      assert {:ok, _} = delete_person(person)
    end
  end

  defp delete_person(person) do
    new()
    |> delete(:person, person)
    |> delete_blob(:avatar, fn ctx -> ctx.person.avatar end)
    |> Repo.transaction()
  end

  defp insert_person(attrs) do
    changeset = Person.changeset(%Person{}, attrs)

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:insert_person, changeset)
    |> Upload.Multi.handle_changes(:person, :insert_person, changeset, :avatar,
      key_function: &key_function/1,
      canned_acl: :public,
      on_upload: fn _repo, _changes ->
        Logger.info("on_upload called")
        {:ok, nil}
      end
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{person: person}} -> {:ok, person}
      error -> error
    end
  end

  defp update_person(person, attrs) do
    changeset = Person.changeset(person, attrs)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:update_person, changeset)
    |> Upload.Multi.handle_changes(:person, :update_person, changeset, :avatar,
      key_function: &key_function/1,
      canned_acl: :public
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{person: person}} -> {:ok, person}
      error -> error
    end
  end

  defp key_function(user) do
    "uploads/users/#{user.id}/avatar"
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
