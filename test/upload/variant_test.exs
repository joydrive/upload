defmodule Upload.VariantTest do
  use ExUnit.Case
end

#   alias Upload.Storage
#   alias Upload.Blob
#   alias Upload.Variant
#   alias FileStore.Adapters.Memory

#   @blob %Blob{key: "abc"}
#   @transforms [&__MODULE__.small_transform/3]

#   describe "new/2" do
#     test "constructs a new variant" do
#       variant = Variant.new(@blob)
#       assert variant.blob == @blob
#       assert variant.transforms == []
#     end

#     test "describes a variant" do
#       variant = Variant.new(@blob, :small, @transforms)
#       assert variant.blob == @blob
#       assert variant.transforms == @transforms
#     end
#   end

#   describe "transform/2" do
#     test "appends transformations" do
#       variant = Variant.new(@blob, foo: "bar")
#       variant = Variant.transform(variant, biz: "buzz")
#       assert variant.blob == @blob
#       assert variant.transforms == [foo: "bar", biz: "buzz"]
#     end
#   end

#   describe "create/1" do
#     @path "test/fixtures/image.jpg"

#     setup do
#       start_supervised!(Memory)
#       :ok
#     end

#     test "transforms an image" do
#       variant = Variant.new(@blob, small: &small_transform/3)
#       assert :ok = Storage.upload(@path, @blob.key)
#       assert {:ok, key} = Variant.create(variant)
#       assert {:ok, _} = Storage.stat(key)
#       assert {:ok, tmp} = Plug.Upload.random_file("upload_test")
#       assert :ok = Storage.download(key, tmp)
#       assert {:ok, %{width: 768, height: 480}} = Upload.Stat.Image.stat(tmp)
#       assert :ok = File.rm(tmp)
#     end
#   end

#   defp small_transform(source, dest, :small) do
#     dbg(dest)

#     with {:ok, image} <- Image.open(source),
#          {:ok, image} <- Image.thumbnail(image, "768x480", crop: :center),
#          {:ok, _} <- Image.write(image, dest <> ".jpg"),
#          :ok <- File.cp(dest <> ".jpg", dest),
#          :ok <- File.rm(dest <> ".jpg") do
#       :ok
#     end
#   end
# end

# defmodule Upload.VariantTest do
#   use Upload.DataCase

#   import Upload.Changeset

#   alias Upload.Test.Person

#   @path "test/fixtures/image.jpg"
#   @upload %Plug.Upload{
#     path: @path,
#     filename: "image.jpg",
#     content_type: "image/jpeg"
#   }

#   describe "cast_attachment_variant/3" do
#     test "accepts a Plug.Upload" do
#       changeset = change_person(%{avatar: @upload})

#       dbg(changeset)

#       assert changeset.valid?
#       assert changeset.changes.avatar
#       assert changeset.changes.avatar.action == :insert
#       assert changeset.changes.avatar.changes.key
#       assert changeset.changes.avatar.changes.path
#       assert changeset.changes.avatar.changes.filename
#     end
#   end

#   defp change_person(attrs, opts \\ []) do
#     %Person{}
#     |> Person.changeset(attrs)
#     |> cast_attachment_variant(:avatar, :small, &small_transform/1)
#   end

# defp small_transform(path) do

#   with {:ok, image} <- Image.open!(path),
#        {:ok, image} <- Image.thumbnail!("768x480", crop: :center) do
#     {:ok, image}
#   end

#   # path
#   # |> Image.open!(path)
#   # |> Image.thumbnail!("768x480", crop: :center)

#   # dbg(path)

#   # {:ok, path}
# end
# end
