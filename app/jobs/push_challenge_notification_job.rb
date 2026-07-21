# Delivers a system push notification to a human opponent when a challenge lands
# in their inbox. Enqueued from the Fight create broadcast for human opponents;
# bots never have subscriptions. No-ops cleanly if the fight vanished, is no
# longer pending, or the opponent has no subscriptions, so it is safe to retry.
# Held back until the opponent's pending pile reaches their configured
# push_min_pending_challenges, so a user can choose to be pinged only once
# challenges stack up.
class PushChallengeNotificationJob < ApplicationJob
  queue_as :default

  # @param fight_id [Integer]
  def perform(fight_id)
    fight = Fight.find_by(id: fight_id)
    return unless fight&.pending?

    opponent = fight.opponent
    return if opponent.bot? || opponent.user_id.nil?
    return if opponent.incoming_challenges.count < opponent.user.push_min_pending_challenges

    subscriptions = PushSubscription.where(user_id: opponent.user_id)
    return if subscriptions.none?

    payload = payload_for(fight)
    subscriptions.each { |subscription| safe_deliver(subscription, payload) }
  end

  private

  def payload_for(fight)
    challenger = fight.challenger
    {
      title: "New challenge!",
      body: "#{challenger.display_name} (#{Belt.name_for(fight.challenger_belt)}) challenges you",
      url: Rails.application.routes.url_helpers.root_path
    }.to_json
  end

  # Delivery errors beyond the gone-subscription case (handled in the model) are
  # logged and swallowed so one bad push service can't fail the whole batch.
  def safe_deliver(subscription, payload)
    subscription.deliver(payload)
  rescue => e
    Rails.logger.warn("PushChallengeNotificationJob delivery failed: #{e.class}: #{e.message}")
  end
end
