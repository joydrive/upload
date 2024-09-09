defmodule Upload.Testing do
  @moduledoc """
  Contains helpers for use with testing uploads.
  """

  def list_uploaded_keys do
    Enum.to_list(Upload.Storage.list!())
  end

  defmacro __using__(_) do
    quote do
      alias Upload.Testing

      # Should limit this with ellipses after a certain amount
      defp formatted_uploaded_keys do
        Enum.map_join(Upload.Testing.list_uploaded_keys(), "\n", fn key -> "- '#{key}'" end)
      end

      defmacro assert_uploaded(argument) do
        quote do
          case unquote(argument) do
            %Upload.Blob{key: key} ->
              assert key in Upload.Testing.list_uploaded_keys(), """
              Expected #{unquote(Macro.to_string(argument))} to be uploaded.

              I could not find an upload matching '#{key}'.

              Files that were uploaded:

              #{formatted_uploaded_keys()}
              """

            key when is_binary(key) ->
              assert key in Upload.Testing.list_uploaded_keys(), """
              Expected #{unquote(Macro.to_string(argument))} to be uploaded.

              I could not find an upload matching '#{key}'.

              Files that were uploaded:

              #{formatted_uploaded_keys()}
              """

            unexpected ->
              raise "Expected #{unquote(Macro.to_string(argument))} to be a Blob struct or string key but it is #{inspect(unexpected)}."
          end
        end
      end

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
        end
      end
    end
  end
end
