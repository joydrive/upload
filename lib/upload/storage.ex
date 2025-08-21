defmodule Upload.Storage do
  @moduledoc false

  alias FileStore.Middleware.Errors
  alias Upload.FileStore.Middleware.Telemetry

  use FileStore.Config, otp_app: :upload

  def init(config) do
    config
    |> add_middleware(Errors)
    |> add_middleware(Telemetry)
  end

  defp add_middleware(config, middleware) do
    Keyword.update(config, :middleware, [middleware], fn middlewares ->
      if middleware in middlewares do
        middlewares
      else
        [middleware | middlewares]
      end
    end)
  end
end
