import Config

if config_env() == :dev do
  config :esbuild,
    version: "0.25.0",
    legion_web: [
      args: ~w(js/app.js --bundle --target=es2020 --outfile=../priv/static/app.js),
      cd: Path.expand("../assets", __DIR__),
      env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
    ]

  config :tailwind,
    version: "4.1.0",
    legion_web: [
      args: ~w(--input=css/app.css --output=../priv/static/app.css),
      cd: Path.expand("../assets", __DIR__)
    ]
end

config :phoenix, :json_library, Jason

config :logger, level: :warning
