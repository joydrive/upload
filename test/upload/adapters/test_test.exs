defmodule Upload.Adapters.TestTest do
  use ExUnit.Case, async: true

  alias Upload.Adapters.Test, as: Adapter

  doctest Upload.Adapters.Test

  @fixture Path.expand("../../fixtures/text.txt", __DIR__)
  @upload %Upload{path: @fixture, filename: "text.txt", key: "foo/text.txt"}

  test "get_uploads/1 and put_upload/1" do
    assert Adapter.get_uploads() == %{}
    Adapter.put_upload(@upload)
    assert Adapter.get_uploads() == %{"foo/text.txt" => @upload}
  end

  test "transfer/1 adds the upload to state" do
    assert Adapter.get_uploads() == %{}
    assert {:ok, %Upload{key: key}} = Adapter.transfer(@upload)
    assert Map.get(Adapter.get_uploads(), key) == %Upload{@upload | status: :transferred}
  end

  test "get_url/1 just returns the key" do
    assert Adapter.get_url("foo/bar.txt") == "foo/bar.txt"
  end

  test "get_signed_url/2" do
    assert Adapter.get_signed_url("foo/bar.txt", []) == {:ok, "foo/bar.txt"}
  end

  test "delete/1 removes the upload from the state" do
    assert {:ok, %Upload{key: key}} = Adapter.transfer(@upload)
    refute Adapter.get_uploads() == %{}

    assert :ok = Adapter.delete(key)
    assert %{} == Adapter.get_uploads()
  end
end
