defmodule Upload.Telemetry do
  require Logger

  def attach_default_logger do
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
        [:upload, :analyze, :start],
        [:upload, :analyze, :stop],
        [:upload, :analyze, :exception],
        [:upload, :stat, :start],
        [:upload, :stat, :stop],
        [:upload, :stat, :exception]
      ],
      &__MODULE__.handle_event/4,
      nil
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
        _config
      ) do
    elapsed = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.info(
      "Transformed variant #{variant} with format #{format} of #{blob_path} kind in #{elapsed}ms"
    )
  end

  def handle_event(
        [:upload, :storage_upload, :stop],
        measurements,
        %{key: key},
        _config
      ) do
    elapsed = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.info("Uploaded #{key} in #{elapsed}ms")
  end

  def handle_event(
        [:upload, :storage_download, :stop],
        measurements,
        %{key: key},
        _config
      ) do
    elapsed = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.info("Downloaded #{key} in #{elapsed}ms")
  end

  def handle_event(
        [:upload, :storage_delete, :stop],
        measurements,
        %{key: key},
        _config
      ) do
    elapsed = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.info("Deleted blob #{key} in #{elapsed}ms")
  end

  def handle_event(_event, _measurements, _metadata, _config) do
    # Logger.info("Event: #{inspect(event)}")
    # Logger.info("Measurements: #{inspect(measurements)}")
    # Logger.info("Metadata: #{inspect(metadata)}")
  end
end
