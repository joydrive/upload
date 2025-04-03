defmodule Upload.Testing do
  @moduledoc """
  Contains helpers for use with testing uploads.

  ## Usage

  Use this module and use the functions provided for testing.

  ```elixir
  defmodule YourTest.Module do
    use Upload.Testing

    test "some test" do
      person = insert_person(attrs)

      assert_uploaded(person.avatar)
    end
  end
  ```
  """

  @spec list_uploaded_keys() :: list()
  def list_uploaded_keys do
    Enum.to_list(Upload.Storage.list!())
  end

  # Should limit this with ellipses after a certain amount?
  @doc false
  def formatted_uploaded_keys do
    Enum.map_join(Upload.Testing.list_uploaded_keys(), "\n", fn key -> "- '#{key}'" end)
  end

  @spec assert_uploaded(Upload.Blob.t() | String.t() | any()) :: Macro.output()
  @doc """
  Asserting that the argument was uploaded. Can be an `Upload.Blob` or a `String` storage key.
  """
  defmacro assert_uploaded(argument) do
    quote do
      case unquote(argument) do
        %Upload.Blob{key: key} ->
          assert key in Upload.Testing.list_uploaded_keys(), """
          Expected #{unquote(Macro.to_string(argument))} to be uploaded.

          I could not find an upload matching '#{key}'.

          Files that were uploaded:

          #{Upload.Testing.formatted_uploaded_keys()}
          """

        key when is_binary(key) ->
          assert key in Upload.Testing.list_uploaded_keys(), """
          Expected #{unquote(Macro.to_string(argument))} to be uploaded.

          I could not find an upload matching '#{key}'.

          Files that were uploaded:

          #{Upload.Testing.formatted_uploaded_keys()}
          """

        unexpected ->
          raise "Expected #{unquote(Macro.to_string(argument))} to be a Blob struct or string key but it is #{inspect(unexpected)}."
      end

      :ok
    end
  end

  @doc """
  Refute that the argument was uploaded. Can be an `Upload.Blob` or a `String` storage key.
  """
  @spec refute_uploaded(Upload.Blob.t() | String.t() | any()) :: Macro.output()
  defmacro refute_uploaded(argument) do
    quote do
      case unquote(argument) do
        %Upload.Blob{key: key} ->
          refute key in Upload.Testing.list_uploaded_keys(), """
          Expected #{unquote(Macro.to_string(argument))} to not be uploaded.

          Found an upload matching '#{key}'.
          """

        key when is_binary(key) ->
          assert key in Upload.Testing.list_uploaded_keys(), """
          Expected #{unquote(Macro.to_string(argument))} to not be uploaded.

          Found an upload matching '#{key}'.
          """

        unexpected ->
          raise "Expected #{unquote(Macro.to_string(argument))} to be an uploaded Blob struct or key but it is #{inspect(unexpected)}."
      end

      :ok
    end
  end

  defmacro __using__(_) do
    quote do
      require Upload.Testing
      import Upload.Testing
    end
  end
end
