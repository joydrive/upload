defmodule Upload.Config do
  @moduledoc false

  def repo, do: Application.fetch_env!(:upload, :repo)
  def vault, do: Application.fetch_env!(:upload, :vault)
  def analyzers, do: Application.get_env(:upload, :analyzers) || [Upload.Stat.Image]
end
