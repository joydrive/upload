defmodule Upload.Test.Repo.Migrations.AddUpload do
  use Ecto.Migration

  def up, do: Upload.Migrations.up()

  def down, do: Upload.Migrations.down()
end
