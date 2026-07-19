require "web-push"

# VAPID credentials + subject for Web Push. Resolution order:
#   1. VAPID_PUBLIC_KEY / VAPID_PRIVATE_KEY from ENV (production and dev override).
#   2. In development, a keypair persisted to tmp/vapid.json (git-ignored),
#      auto-generated on first boot so dev works with zero setup.
#   3. In test, an ephemeral in-memory keypair (specs stub delivery).
#   4. Otherwise (e.g. production with no ENV) push is left unconfigured and the
#      opt-in UI hides itself.
#
# Generate a production keypair with `bin/rails push:generate_vapid`.
module Push
  DEV_KEY_FILE = Rails.root.join("tmp", "vapid.json")
  DEFAULT_SUBJECT = "mailto:hello@kungfumadness.invalid"

  class << self
    # @return [String, nil] the VAPID public key (base64url, the applicationServerKey)
    def public_key
      credentials[:public_key]
    end

    # @return [String, nil] the VAPID private key (base64url)
    def private_key
      credentials[:private_key]
    end

    # @return [String] the VAPID subject — a mailto: for the push service contact
    def subject
      mail_from = ENV["MAIL_FROM"].presence
      mail_from ? "mailto:#{mail_from}" : DEFAULT_SUBJECT
    end

    # @return [Hash] the vapid: option web-push expects
    def vapid_details
      { subject: subject, public_key: public_key, private_key: private_key }
    end

    # @return [Boolean] whether push is usable (both keys present)
    def configured?
      public_key.present? && private_key.present?
    end

    private

    def credentials
      @credentials ||= resolve_credentials
    end

    def resolve_credentials
      if ENV["VAPID_PUBLIC_KEY"].present? && ENV["VAPID_PRIVATE_KEY"].present?
        { public_key: ENV["VAPID_PUBLIC_KEY"], private_key: ENV["VAPID_PRIVATE_KEY"] }
      elsif Rails.env.development?
        load_or_generate_dev_keys
      elsif Rails.env.test?
        generate_keypair
      else
        { public_key: nil, private_key: nil }
      end
    end

    def load_or_generate_dev_keys
      return JSON.parse(DEV_KEY_FILE.read).symbolize_keys if DEV_KEY_FILE.exist?

      generate_keypair.tap { |keys| DEV_KEY_FILE.write(JSON.pretty_generate(keys)) }
    end

    def generate_keypair
      key = WebPush.generate_key
      { public_key: key.public_key, private_key: key.private_key }
    end
  end
end
