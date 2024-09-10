defmodule UploadOld.UploaderTest do
  use ExUnit.Case, async: true

  defmodule MyUploader do
    use UploadOld.Uploader

    def cast(file, _opts \\ []) do
      with {:ok, upload} <- UploadOld.cast(file, prefix: ["logos"]) do
        extension = UploadOld.get_extension(upload)

        if Enum.member?(~w(.png), extension) do
          {:ok, upload}
        else
          {:error, "invalid"}
        end
      end
    end
  end

  test "delegates by default" do
    assert {:ok, upload} = MyUploader.cast_path("/path/to/foo.png")
    assert {:ok, %UploadOld{}} = MyUploader.transfer(upload)
  end

  test "allows overriding" do
    good = %Plug.Upload{path: "/path/to/foo.png", filename: "foo.png"}
    bad = %Plug.Upload{path: "/path/to/foo.jpg", filename: "foo.jpg"}

    assert {:ok, %UploadOld{}} = MyUploader.cast(good)
    assert {:error, "invalid"} = MyUploader.cast(bad)
  end
end
