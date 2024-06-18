defmodule Upload.Test.Vault do
  @moduledoc "The default Upload vault. Should be overridden. TODO remove unless in tests?"
  use Cloak.Vault, otp_app: :upload
end
