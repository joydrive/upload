defmodule Upload.Telemetry do
  require Logger

  alias Upload.JSON

  @doc """
  - `:encode` — If true, log output is encoded as JSON; otherwise, structured logging is used. Default: `true`.
  - `:level` — Sets the log level for output. Default: `:info`.
  """
  def attach_default_logger(opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:level, :info)
      |> Keyword.put_new(:encode, true)

    :telemetry.attach_many(
      "upload-default-logger",
      [
        [:upload, :transform, :start],
        [:upload, :transform, :stop],
        [:upload, :transform, :exception],
        [:upload, :storage_upload, :start],
        [:upload, :storage_upload, :stop],
        [:upload, :storage_upload, :exception],
        [:upload, :storage_download, :start],
        [:upload, :storage_download, :stop],
        [:upload, :storage_download, :exception],
        [:upload, :storage_delete, :start],
        [:upload, :storage_delete, :stop],
        [:upload, :storage_delete, :exception],
        [:upload, :storage_delete_all, :start],
        [:upload, :storage_delete_all, :stop],
        [:upload, :storage_delete_all, :exception],
        [:upload, :analyze, :start],
        [:upload, :analyze, :stop],
        [:upload, :analyze, :exception],
        [:upload, :stat, :start],
        [:upload, :stat, :stop],
        [:upload, :stat, :exception]
      ],
      &__MODULE__.handle_event/4,
      opts
    )
  end

  def handle_event(
        [:upload, :transform, :stop],
        measurements,
        %{
          blob_path: blob_path,
          variant: variant,
          format: format
        },
        opts
      ) do
    elapsed = System.convert_time_unit(measurements.duration, :native, :millisecond)

    log(opts, fn ->
      %{
        event: "transform",
        message:
          "Transformed variant #{variant} with format #{format} from #{blob_path} in #{elapsed}ms",
        variant: variant,
        format: format,
        blob_path: blob_path,
        elapsed: convert(measurements.duration)
      }
    end)
  end

  def handle_event(
        [:upload, :storage_upload, :stop],
        measurements,
        %{key: key},
        opts
      ) do
    elapsed = System.convert_time_unit(measurements.duration, :native, :millisecond)

    log(opts, fn ->
      %{
        event: "storage:upload",
        message: "Uploaded #{key} in #{elapsed}ms",
        key: key,
        elapsed: convert(measurements.duration)
      }
    end)
  end

  def handle_event(
        [:upload, :storage_download, :stop],
        measurements,
        %{key: key},
        opts
      ) do
    elapsed = System.convert_time_unit(measurements.duration, :native, :millisecond)

    log(opts, fn ->
      %{
        event: "storage:download",
        message: "Downloaded #{key} in #{elapsed}ms",
        key: key,
        elapsed: convert(measurements.duration)
      }
    end)
  end

  def handle_event(
        [:upload, :storage_delete, :stop],
        measurements,
        %{key: key},
        opts
      ) do
    elapsed = System.convert_time_unit(measurements.duration, :native, :millisecond)

    log(opts, fn ->
      %{
        event: "storage:delete",
        message: "Deleted #{key} in #{elapsed}ms",
        key: key,
        elapsed: convert(measurements.duration)
      }
    end)
  end

  def handle_event(
        [:upload, :storage_delete_all, :stop],
        measurements,
        %{opts: delete_all_opts},
        opts
      ) do
    elapsed = System.convert_time_unit(measurements.duration, :native, :millisecond)

    log(opts, fn ->
      %{
        event: "storage:delete_all",
        message: "Deleted by prefix #{delete_all_opts[:prefix]} in #{elapsed}ms",
        elapsed: convert(measurements.duration),
        prefix: delete_all_opts[:prefix]
      }
    end)
  end

  def handle_event(_event, _measurements, _metadata, _opts) do
    # Logger.info("Event: #{inspect(event)}")
    # Logger.info("Measurements: #{inspect(measurements)}")
    # Logger.info("Metadata: #{inspect(metadata)}")
  end

  defp log(opts, fun) do
    level = Keyword.fetch!(opts, :level)

    Logger.log(level, fn ->
      output = Map.put(fun.(), :source, "upload")

      if Keyword.fetch!(opts, :encode) do
        JSON.encode_to_iodata!(output)
      else
        "[Upload] #{output.message}"
      end
    end)
  end

  defp convert(value), do: System.convert_time_unit(value, :native, :microsecond)
end
