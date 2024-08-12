defmodule Upload.Stat.ImageTest do
  @moduledoc false

  use Upload.DataCase

  alias Upload.Stat.Image

  describe "stat/2" do
    test "returns {:ok, %{}} when file is not an image MIME type" do
      assert Image.stat("path", "not-a-image") == {:ok, %{}}
    end

    test "returns {:ok, %{}} when the file does not exist" do
      assert Image.stat("path", "image/png") == {:ok, %{}}
    end
  end
end
