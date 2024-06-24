Mix.Task.run("ecto.drop", ["-r", "Upload.Test.Repo"])
Mix.Task.run("ecto.create", ["-r", "Upload.Test.Repo"])
Mix.Task.run("ecto.migrate", ["-r", "Upload.Test.Repo"])

{:ok, _} = Upload.Test.Vault.start_link()

{:ok, _} = Upload.Test.Repo.start_link()
Ecto.Adapters.SQL.Sandbox.mode(Upload.Test.Repo, :manual)
ExUnit.start(exclude: [pending: true])
