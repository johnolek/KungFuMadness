class PushSubscription < ApplicationRecord
  belongs_to :user

  validates :endpoint, presence: true, uniqueness: true
  validates :p256dh_key, :auth_key, presence: true

  # Creates or refreshes the subscription keyed by its browser-issued endpoint.
  # A browser re-subscribing (new keys, same endpoint, or the same device under a
  # different user) overwrites in place, so there is exactly one row per endpoint.
  #
  # @param user [User]
  # @param endpoint [String]
  # @param p256dh_key [String]
  # @param auth_key [String]
  # @param user_agent [String, nil]
  # @return [PushSubscription]
  def self.upsert_for(user:, endpoint:, p256dh_key:, auth_key:, user_agent: nil)
    subscription = find_or_initialize_by(endpoint: endpoint)
    subscription.update(user: user, p256dh_key: p256dh_key, auth_key: auth_key, user_agent: user_agent)
    subscription
  end

  # Sends an encrypted payload to this subscription's push service. A subscription
  # the browser has abandoned (404/410) is pruned so it never gets tried again.
  #
  # @param payload [String, Hash] JSON string or hash serialized to the push body
  # @return [Boolean] true on delivery, false when the subscription was gone
  def deliver(payload)
    WebPush.payload_send(
      message: payload.is_a?(String) ? payload : payload.to_json,
      endpoint: endpoint,
      p256dh: p256dh_key,
      auth: auth_key,
      vapid: Push.vapid_details,
      urgency: "high"
    )
    true
  rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
    destroy
    false
  end
end
