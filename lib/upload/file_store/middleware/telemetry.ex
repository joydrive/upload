defmodule Upload.FileStore.Middleware.Telemetry do
  @moduledoc """
  This module adds telemetry spans to storage operations.

  See the documentation for `FileStore.Middleware` for more information.
  """

  @enforce_keys [:__next__]
  defstruct [:__next__]

  def new(store) do
    %__MODULE__{__next__: store}
  end

  defimpl FileStore do
    def stat(store, key) do
      FileStore.stat(store.__next__, key)
    end

    def delete(store, key) do
      metadata = %{key: key}

      :telemetry.span(
        [:upload, :storage_delete],
        metadata,
        fn ->
          {FileStore.delete(store.__next__, key), metadata}
        end
      )
    end

    def delete_all(store, opts) do
      metadata = %{opts: opts}

      :telemetry.span(
        [:upload, :storage_delete_all],
        metadata,
        fn ->
          {FileStore.delete_all(store.__next__, opts), metadata}
        end
      )
    end

    def write(store, key, content, opts) do
      FileStore.write(store.__next__, key, content, opts)
    end

    def read(store, key) do
      FileStore.read(store.__next__, key)
    end

    def copy(store, src, dest) do
      FileStore.copy(store.__next__, src, dest)
    end

    def rename(store, src, dest) do
      FileStore.rename(store.__next__, src, dest)
    end

    def put_access_control_list(store, key, acl) do
      FileStore.put_access_control_list(store.__next__, key, acl)
    end

    def set_tags(store, key, tags) do
      FileStore.set_tags(store.__next__, key, tags)
    end

    def get_tags(store, key) do
      FileStore.get_tags(store.__next__, key)
    end

    def upload(store, source, key) do
      metadata = %{key: key, path: source}

      :telemetry.span(
        [:upload, :storage_upload],
        metadata,
        fn ->
          {FileStore.upload(store.__next__, source, key), metadata}
        end
      )
    end

    def download(store, key, dest) do
      metadata = %{key: key, path: dest}

      :telemetry.span(
        [:upload, :storage_download],
        metadata,
        fn ->
          {FileStore.download(store.__next__, key, dest), metadata}
        end
      )
    end

    def get_public_url(store, key, opts) do
      FileStore.get_public_url(store.__next__, key, opts)
    end

    def get_signed_url(store, key, opts) do
      FileStore.get_signed_url(store.__next__, key, opts)
    end

    def list!(store, opts) do
      FileStore.list!(store.__next__, opts)
    end
  end
end
