require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  config.cache_store = :memory_store

  # Solid Queue on the single primary database (no `connects_to`).
  config.active_job.queue_adapter = :solid_queue

  # A missing/misconfigured SMTP server must not 500 a sign-in request; the magic
  # link simply won't send until the SMTP_* env vars are set.
  config.action_mailer.raise_delivery_errors = false

  # Host for links in emails (the magic-link sign-in URL). Prefer MAIL_HOST, else
  # derive from the WebAuthn origin the app is already deployed under, else localhost.
  mail_host = ENV["MAIL_HOST"].presence ||
              (ENV["WEBAUTHN_ORIGIN"].present? ? URI(ENV["WEBAUTHN_ORIGIN"]).host : "localhost")
  config.action_mailer.default_url_options = { host: mail_host, protocol: "https" }

  # Prefer the SMTP2GO HTTP API when a key is set — it gives an explicit, logged
  # delivery result (see Smtp2goDelivery) over HTTPS. Otherwise fall back to
  # provider-agnostic SMTP, configured entirely from the environment. `.compact`
  # drops unset keys so an incomplete config degrades gracefully rather than
  # sending garbage. Magic-link sign-in and the email-verification flow need this.
  if ENV["SMTP2GO_API_KEY"].present?
    # Settings (the API key) are seeded where the method is registered, in
    # config/initializers/smtp2go.rb — see the note there on boot order.
    config.action_mailer.delivery_method = :smtp2go
  else
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.smtp_settings = {
      address: ENV["SMTP_ADDRESS"],
      port: ENV.fetch("SMTP_PORT", 587).to_i,
      user_name: ENV["SMTP_USERNAME"],
      password: ENV["SMTP_PASSWORD"],
      authentication: ENV.fetch("SMTP_AUTHENTICATION", "plain").to_sym,
      domain: ENV["SMTP_DOMAIN"],
      enable_starttls_auto: true
    }.compact
  end

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
