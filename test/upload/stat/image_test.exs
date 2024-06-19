defmodule Upload.Stat.ImageTest do
  @moduledoc false

  use Upload.DataCase
  
  describe "stat/2" do
    test "returns {:ok, nil} when file is not an image MIME type" do
      assert Upload.Stat.Image.stat("path", "not-a-image") == {:ok, nil}
    end

    test "returns {:ok, nil} when the file does not exist" do
      assert Upload.Stat.Image.stat("path", "image/png") == {:ok, nil}
    end
  end
end
