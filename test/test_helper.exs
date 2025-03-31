Mix.Task.run("ecto.drop", ["--quiet", "-r", "Upload.Test.Repo"])
Mix.Task.run("ecto.create", ["--quiet", "-r", "Upload.Test.Repo"])
Mix.Task.run("ecto.migrate", ["--quiet", "-r", "Upload.Test.Repo"])

{:ok, _} = Upload.Test.Vault.start_link()

{:ok, _} = Upload.Test.Repo.start_link()
Ecto.Adapters.SQL.Sandbox.mode(Upload.Test.Repo, :manual)
Upload.Telemetry.attach_default_logger()
ExUnit.start(exclude: [pending: true], capture_log: true)
