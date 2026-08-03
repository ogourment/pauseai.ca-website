import Config

atdd_port = System.get_env("ATDD_PORT", "4116") |> String.to_integer()

# Only in tests, remove the complexity from the password hashing algorithm
config :argon2_elixir, t_cost: 1, m_cost: 8

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :pauseai_ca, PauseAiCa.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "pauseai_ca_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :pauseai_ca, PauseAiCaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: atdd_port],
  check_origin: ["//127.0.0.1:#{atdd_port}"],
  secret_key_base: "5Vkv9MzGeaVJ8q0JxD/hSW9dy6yp4ICThE+njQukPZmS5oWfYq0KFVadquCale9t",
  server: false

config :phoenix_test,
  otp_app: :pauseai_ca,
  base_url: System.get_env("ATDD_BASE_URL", "http://127.0.0.1:#{atdd_port}"),
  playwright: [
    screenshot_dir: "tmp/atdd/screenshots",
    trace_dir: "tmp/atdd/traces",
    timeout: 8_000
  ]

config :acceptance_harness, :harness,
  app_name: "PauseAI Canada",
  otp_app: :pauseai_ca,
  site_title: "PauseAI Canada acceptance evidence",
  evidence_dir: "tmp/atdd",
  screenshot_dir: "tmp/atdd/screenshots",
  trace_dir: "tmp/atdd/traces",
  commit_sha_env: ["PAUSEAI_CA_GIT_SHA", "GITHUB_SHA"]

# In test we don't send emails
config :pauseai_ca, PauseAiCa.Mailer, adapter: Swoosh.Adapters.Test

# Member of parliament lookups are answered by a local stub, never the network
config :pauseai_ca, :represent_req_options, plug: &PauseAiCa.RepresentStub.call/1

# Mailing-list subscriptions likewise never leave the test process
config :pauseai_ca, :brevo_req_options, plug: &PauseAiCa.BrevoStub.call/1
config :pauseai_ca, :brevo_api_key, "test-key"
config :pauseai_ca, :brevo_list_ids, [1]

config :pauseai_ca, :campaign_sender, {"PauseAI Canada", "campaigns@example.org"}

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Letters go to the sender, never to a member of parliament.
config :pauseai_ca, :campaign_rehearsal, true

# Tests submit instantly; the human-pace check is exercised explicitly.
config :pauseai_ca, :campaign_min_seconds, 0
