defmodule Upload.Test.Repo do
  @moduledoc false

  use Ecto.Repo, otp_app: :upload, adapter: Ecto.Adapters.Postgres
end
