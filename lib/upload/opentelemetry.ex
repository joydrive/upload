defmodule Upload.OpenTelemetry do
  require Logger

  @tracer_id __MODULE__

  def attach do
    :telemetry.attach_many(
      "upload-opentelemetry",
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
        [:upload, :analyze, :start],
        [:upload, :analyze, :stop],
        [:upload, :analyze, :exception],
        [:upload, :stat, :start],
        [:upload, :stat, :stop],
        [:upload, :stat, :exception]
      ],
      &__MODULE__.handle_event/4,
      %{}
    )
  end

  def handle_event(
        [_, _, :start] = event,
        _measurements,
        metadata,
        %{}
      ) do
    OpentelemetryTelemetry.start_telemetry_span(
      @tracer_id,
      span_name(event),
      metadata,
      %{}
    )

    add_start_attributes(event, metadata)

    :ok
  end

  def handle_event(
        [_, _, :stop] = event,
        _measurements,
        metadata,
        %{}
      ) do
    add_stop_attributes(event, metadata)

    OpentelemetryTelemetry.set_current_telemetry_span(@tracer_id, metadata)
    OpentelemetryTelemetry.end_telemetry_span(@tracer_id, metadata)

    :ok
  end

  def handle_event(
        [_, _, :exception],
        %{duration: _duration},
        %{kind: kind, reason: reason, stacktrace: stacktrace} = metadata,
        _
      ) do
    ctx = OpentelemetryTelemetry.set_current_telemetry_span(@tracer_id, metadata)
    status = OpenTelemetry.status(:error, to_string(reason))
    exception = Exception.normalize(kind, reason, stacktrace)

    OpenTelemetry.Span.record_exception(ctx, exception, stacktrace, [])
    OpenTelemetry.Tracer.set_status(status)
    OpentelemetryTelemetry.end_telemetry_span(@tracer_id, metadata)
    :ok
  end

  defp span_name([:upload, :transform, :start]), do: "Upload.transform"
  defp span_name([:upload, :storage_upload, :start]), do: "Upload.storage_upload"
  defp span_name([:upload, :storage_download, :start]), do: "Upload.storage_download"
  defp span_name([:upload, :storage_delete, :start]), do: "Upload.storage_delete"
  defp span_name([:upload, :analyze, :start]), do: "Upload.analyze"
  defp span_name([:upload, :stat, :start]), do: "Upload.stat"

  defp add_start_attributes([:upload, :transform, :start], %{
         original_blob_key: original_blob_key,
         blob_path: blob_path,
         variant: variant,
         format: format
       }) do
    OpenTelemetry.Span.set_attributes(OpenTelemetry.Tracer.current_span_ctx(),
      "upload.transform.original_blob_key": original_blob_key,
      "upload.transform.blob_path": blob_path,
      "upload.transform.variant": variant,
      "upload.transform.format": format
    )
  end

  defp add_start_attributes([:upload, :storage_upload, :start], %{key: key, path: path}) do
    OpenTelemetry.Span.set_attributes(OpenTelemetry.Tracer.current_span_ctx(),
      "upload.storage_upload.key": key,
      "upload.storage_upload.path": path
    )
  end

  defp add_start_attributes([:upload, :storage_download, :start], %{key: key, path: path}) do
    OpenTelemetry.Span.set_attributes(OpenTelemetry.Tracer.current_span_ctx(),
      "upload.storage_download.key": key,
      "upload.storage_download.path": path
    )
  end

  defp add_start_attributes([:upload, :storage_delete, :start], %{key: key}) do
    OpenTelemetry.Span.set_attributes(OpenTelemetry.Tracer.current_span_ctx(),
      "upload.storage_delete.key": key
    )
  end

  defp add_start_attributes([:upload, :analyze, :start], %{
         analyzer: analyzer,
         path: path,
         content_type: content_type
       }) do
    OpenTelemetry.Span.set_attributes(OpenTelemetry.Tracer.current_span_ctx(),
      "upload.analyze.analyzer": analyzer,
      "upload.analyze.path": path,
      "upload.analyze.content_type": content_type
    )
  end

  defp add_start_attributes(_, _), do: :ok

  defp add_stop_attributes([:upload, :stat, :stop], %{
         stat: %{
           path: path,
           filename: filename,
           checksum: checksum,
           byte_size: byte_size,
           content_type: content_type,
           metadata: metadata
         }
       }) do
    OpenTelemetry.Span.set_attributes(OpenTelemetry.Tracer.current_span_ctx(),
      "upload.stat.path": path,
      "upload.stat.filename": filename,
      "upload.stat.checksum": checksum,
      "upload.stat.byte_size": byte_size,
      "upload.stat.content_type": content_type
    )

    OpenTelemetry.Span.set_attributes(
      OpenTelemetry.Tracer.current_span_ctx(),
      Enum.map(metadata, fn {key, value} ->
        {"upload.stat.metadata." <> to_string(key), to_string(value)}
      end)
    )
  end

  defp add_stop_attributes(_, _), do: :ok
end
