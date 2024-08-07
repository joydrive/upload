# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
import Config

config :logger, level: :info

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.

if Mix.env() == :test do
  import_config "#{config_env()}.exs"
end
