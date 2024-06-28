defmodule Upload.EncryptedBinary do
  @moduledoc false
  use Cloak.Ecto.Binary, vault: Upload.Config.vault()
end
