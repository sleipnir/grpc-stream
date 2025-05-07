import Config

config :logger,
  backends: [:console],
  truncate: 65536,
  level: :debug

config :logger, :console,
  format: "$date $time [$node]:[$metadata]:[$level]:$message\n",
  metadata: [:pid]

import_config "#{config_env()}.exs"
