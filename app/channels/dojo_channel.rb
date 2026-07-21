## The site-wide "living world" stream every signed-in fighter joins. Carries the
# public heartbeat of the dojo: resolved fights for the ticker and presence
# (who just came online / went offline). Subscribing counts as stepping onto the
# mat — it stamps last_seen_at and announces you online; a ~45s client ping keeps
# that fresh; disconnecting announces you offline.
#
# Presence is DB-backed (Fighter.online reads last_seen_at); these broadcasts are
# just the live nudge, and clients reconcile against the authoritative online list
# they were served on page load.
class DojoChannel < ApplicationCable::Channel
  STREAM = "dojo".freeze

  # Anonymous spectators may watch the stream; only a fighter steps onto the mat
  # (presence stamp + online broadcast).
  def subscribed
    stream_from STREAM

    fighter = current_user&.fighter
    return unless fighter

    fighter.touch(:last_seen_at)
    DojoChannel.broadcast_presence(fighter, online: true)
  end

  def unsubscribed
    fighter = current_user&.fighter
    return unless fighter

    DojoChannel.broadcast_presence(fighter, online: false)
  end

  # Client keep-alive: refreshes presence without a full resubscribe. The browser
  # performs this every ~45s so an open tab keeps the fighter inside the 2-minute
  # online window.
  def ping(_data = {})
    current_user&.fighter&.touch(:last_seen_at)
  end

  # @param payload [Hash] arbitrary event hash pushed to every dojo subscriber
  def self.broadcast_event(payload)
    ActionCable.server.broadcast(STREAM, payload)
  end

  # @param fighter [Fighter]
  # @param online [Boolean]
  def self.broadcast_presence(fighter, online:)
    broadcast_event(event: "presence", online: online, fighter: fighter.presence_payload)
  end

  # A belt change ticker line: "<name> reached Yellow belt" (promotion) or "<name>
  # fell to White belt" (demotion). Fired from any path that settles a belt — a
  # resolved fight, rust decay — so the dojo sees the whole ladder shift, not just
  # who beat whom.
  #
  # @param fighter [Fighter] already at its new belt
  # @param from [Integer] the belt index the fighter held before
  def self.broadcast_belt_change(fighter, from:)
    return if fighter.belt == from

    broadcast_event(
      event: "belt_change",
      direction: fighter.belt > from ? "promotion" : "demotion",
      fighter: fighter.presence_payload,
      from_belt: from,
      from_belt_name: Belt.name_for(from)
    )
  end
end
