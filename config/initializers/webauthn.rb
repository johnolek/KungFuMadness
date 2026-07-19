WebAuthn.configure do |config|
  config.rp_name = ENV.fetch("WEBAUTHN_RP_NAME", "Kung Fu Madness")

  # The Relying Party ID is the domain passkeys are scoped to. "localhost" works
  # for development; production supplies the real host via an env var.
  config.rp_id = ENV.fetch("WEBAUTHN_RP_ID", "localhost")

  # The browser-reported origin must match exactly, scheme and port included.
  # In development the server often lands on a different port (3000-3002 taken by
  # other projects), so allow a range of localhost ports instead of just 3000.
  config.allowed_origins =
    if ENV["WEBAUTHN_ORIGIN"]
      [ ENV["WEBAUTHN_ORIGIN"] ]
    elsif Rails.env.development?
      (3000..3010).map { |port| "http://localhost:#{port}" }
    else
      [ "http://localhost:3000" ]
    end

  config.encoding = :base64url
end
