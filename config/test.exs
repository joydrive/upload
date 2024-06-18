import Config

# Configuration for the test suite
config :upload, ecto_repos: [Upload.Test.Repo]

config :upload, Upload.Test.Repo,
  adapter: Ecto.Adapters.Postgres,
  database: "upload_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  priv: "test/support/"

config :upload, Upload.Test.Vault,
  ciphers: [
    default:
      {Cloak.Ciphers.AES.GCM,
       tag: "AES.GCM.V1", key: Base.decode64!("KyRFNTop589ClLNsY0fNus68AvWKQfUQMKu5LvS8ToQ=")}
  ]

config :upload, Upload.Storage,
  adapter: FileStore.Adapters.Memory,
  base_url: "http://example.com"

config :upload,
  repo: Upload.Test.Repo,
  vault: Upload.Test.Vault
