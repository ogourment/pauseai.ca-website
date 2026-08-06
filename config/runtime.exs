import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/pauseai_ca start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :pauseai_ca, PauseAiCaWeb.Endpoint, server: true
end

# Applies to every environment and runs after config/dev.exs, so this is the
# single source of truth for the port. 4013 is this project's entry in the local
# port registry; deployed slots set PORT explicitly.
config :pauseai_ca, PauseAiCaWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4013"))]

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :pauseai_ca, PauseAiCaWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Gettext translations
        ~r"priv/gettext/.*\.po$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/pauseai_ca_web/router\.ex$"E,
        ~r"lib/pauseai_ca_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

# Which deployment this is. The blue/green deploy sets this; unset means
# production, which carries no badge. Only set when present, or this would
# clobber the value config/dev.exs establishes for local work.
if display_env = System.get_env("PAUSEAI_CA_DISPLAY_ENV") do
  config :pauseai_ca, :display_env, display_env
end

# Google Analytics. Unset means no tracker and no consent banner, which is the
# default everywhere including production until a measurement id is provided.
config :pauseai_ca, :ga_measurement_id, System.get_env("GA_MEASUREMENT_ID")

# Audit events are emitted at :info. LOG_LEVEL raises or lowers the floor;
# set it to debug when diagnosing something.
if level = System.get_env("LOG_LEVEL") do
  config :logger, level: String.to_existing_atom(level)
end

if config_env() == :prod do
  deployment_history_path = System.fetch_env!("PAUSEAI_CA_DEPLOYMENT_HISTORY_PATH")

  config :acceptance_harness, :deployment,
    history_path: deployment_history_path,
    peer_versions_url: System.get_env("PAUSEAI_CA_PEER_VERSIONS_URL"),
    peer_acceptance_url: System.get_env("PAUSEAI_CA_PEER_ACCEPTANCE_URL"),
    page_size: 10

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :pauseai_ca, PauseAiCa.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :pauseai_ca, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :pauseai_ca, PauseAiCaWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  if brevo_api_key = System.get_env("BREVO_API_KEY") do
    config :pauseai_ca, PauseAiCa.Mailer,
      adapter: Swoosh.Adapters.Brevo,
      api_key: brevo_api_key

    # The same key also drives mailing-list subscriptions through the Brevo
    # contacts API. BREVO_LIST_IDS is a comma-separated list of numeric ids.
    config :pauseai_ca, :brevo_api_key, brevo_api_key

    config :pauseai_ca,
           :brevo_list_ids,
           "BREVO_LIST_IDS"
           |> System.get_env("")
           |> String.split(",", trim: true)
           |> Enum.map(&String.to_integer(String.trim(&1)))
  else
    if System.get_env("PHX_SERVER") do
      raise "environment variable BREVO_API_KEY is missing"
    end
  end

  # Divert campaign letters to the sender instead of a member of parliament.
  # Any environment that is not production must set this.
  config :pauseai_ca,
         :campaign_rehearsal,
         System.get_env("CAMPAIGN_REHEARSAL") in ~w(true 1)

  # Close the site to anyone not signed in. Set on staging; left off in
  # production, where the site is meant to be public.
  config :pauseai_ca,
         :require_invited,
         System.get_env("REQUIRE_INVITED") in ~w(true 1)

  # Address campaign letters are sent from when a supporter asks us to send on
  # their behalf. Their own address is used as reply-to.
  config :pauseai_ca,
         :campaign_sender,
         {System.get_env("CAMPAIGN_SENDER_NAME", "PauseAI Canada"),
          System.get_env("CAMPAIGN_SENDER_EMAIL", "info@pauseai.ca")}

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :pauseai_ca, PauseAiCaWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :pauseai_ca, PauseAiCaWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :pauseai_ca, PauseAiCa.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://swoosh.hexdocs.pm/Swoosh.html#module-installation for details.
end
