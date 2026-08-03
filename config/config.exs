import Config

config :logger, level: :warning

if config_env() == :dev do
  config :esbuild,
    version: "0.25.0",
    legion_web: [
      args: ~w(js/app.js --bundle --minify --outfile=../priv/static/app.js),
      cd: Path.expand("../assets", __DIR__)
    ]

  config :tailwind,
    version: "4.1.0",
    legion_web: [
      args: ~w(--minify --input=css/app.css --output=../priv/static/app.css),
      cd: Path.expand("../assets", __DIR__)
    ]

  config :logger, level: :info
end

config :phoenix, :json_library, Jason
