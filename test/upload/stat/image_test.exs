defmodule Upload.Stat.ImageTest do
  @moduledoc false

  use Upload.DataCase

  alias Upload.Stat.Image

  describe "stat/2" do
    test "returns {:ok, nil} when file is not an image MIME type" do
      assert Image.stat("path", "not-a-image") == {:ok, nil}
    end

    test "returns {:ok, nil} when the file does not exist" do
      assert Image.stat("path", "image/png") == {:ok, nil}
    end
  end
end
