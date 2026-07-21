class Fight < ApplicationRecord
  # A challenge cannot be issued to the same opponent within this window of the
  # most recent fight (any status) between the pair. Tunable; the plan's default.
  CHALLENGE_COOLDOWN = 5.minutes

  # How long a pending challenge waits for a response before it lazily expires
  # when next touched, or a daily sweep flips it (see ExpireChallengesJob).
  CHALLENGE_TTL = 7.days

  # A bot treats a challenger as "farming" it once this many fights between the
  # pair land inside FARM_WINDOW — the signal a temperamental bot declines on.
  FARM_LIMIT = 4
  FARM_WINDOW = 24.hours

  belongs_to :challenger, class_name: "Fighter"
  belongs_to :opponent, class_name: "Fighter"
  belongs_to :winner, class_name: "Fighter", optional: true

  has_many :fight_moves, dependent: :destroy
  has_many :fight_rounds, -> { order(:round) }, dependent: :destroy, inverse_of: :fight

  enum :status, { pending: 0, resolved: 1, declined: 2, expired: 3 }

  validates :challenger_belt, :challenger_xp, :opponent_belt, :opponent_xp,
            presence: true, numericality: { only_integer: true }
  validates :expires_at, presence: true
  validate :distinct_fighters

  # Living-world broadcasts ride the transaction: a fresh challenge is mail to the
  # opponent; a status flip to resolved feeds the dojo ticker and tells the
  # challenger their fight settled; a flip to declined tells the challenger. On
  # commit so a rolled-back fight never announces itself.
  after_create_commit :broadcast_challenge_received
  after_update_commit :broadcast_status_change

  scope :for_fighter, ->(fighter) { where(challenger: fighter).or(where(opponent: fighter)) }
  scope :between, ->(a, b) {
    where(challenger: a, opponent: b).or(where(challenger: b, opponent: a))
  }
  scope :past_expiry, -> { where(expires_at: ..Time.current) }
  scope :recent, -> { order(created_at: :desc) }
  scope :recently_resolved, -> { resolved.order(resolved_at: :desc) }

  # Raised when a challenge can't be created for a game-rule reason (cooldown,
  # self-challenge). Carries a human message for the controller flash.
  class ChallengeError < StandardError; end

  # Issues a sealed challenge: snapshots both fighters' belt/XP at this instant,
  # writes the challenger's three committed move rows, and starts the response
  # clock. Everything happens in one transaction so a half-built challenge never
  # exists. Rejects self-challenges and pairs still inside the cooldown window.
  #
  # @param challenger [Fighter]
  # @param opponent [Fighter]
  # @param moves [Array<Hash>] three rounds of { round:, attack_height:, attack_style:, block_height: }
  # @return [Fight] the persisted pending fight
  # @raise [ChallengeError] on self-challenge or an active cooldown
  def self.create_challenge!(challenger:, opponent:, moves:)
    raise ChallengeError, "You can't challenge yourself." if challenger == opponent

    if pending.exists?(challenger: challenger, opponent: opponent)
      raise ChallengeError, "You already have a challenge out to them — wait for their answer."
    end

    if between(challenger, opponent).where(created_at: CHALLENGE_COOLDOWN.ago..).exists?
      raise ChallengeError, "You've faced #{opponent.name} too recently — wait out the cooldown."
    end

    transaction do
      fight = create!(
        challenger: challenger,
        opponent: opponent,
        status: :pending,
        challenger_belt: challenger.belt,
        challenger_xp: challenger.xp,
        opponent_belt: opponent.belt,
        opponent_xp: opponent.xp,
        expires_at: CHALLENGE_TTL.from_now
      )
      fight.write_moves!(fighter: challenger, moves: moves)
      fight
    end
  end

  # Opponent commits their moves and the fight resolves. Row-locked and guarded
  # so a double-submit is a clean no-op: the second caller sees a non-pending
  # status and returns without touching anything. Uses the SNAPSHOT belts for
  # both combat and XP, then applies XP, belt settlement, and win/loss/draw
  # counters to BOTH real fighters.
  #
  # @param moves [Array<Hash>] the opponent's three rounds
  # @param rng [Random] injectable dice source (seed for deterministic specs)
  # @return [Boolean] true if this call resolved the fight, false if it was a no-op
  def respond!(moves:, rng: Random.new)
    with_lock do
      return false unless actionable?

      write_moves!(fighter: opponent, moves: moves)

      result = FightResolver.new(
        challenger_moves: ordered_moves(challenger),
        opponent_moves: ordered_moves(opponent),
        challenger_belt: challenger_belt,
        opponent_belt: opponent_belt,
        rng: rng
      ).resolve

      persist_result!(result)
      true
    end
  end

  # Opponent declines the challenge. Locked + pending-guarded; increments the
  # opponent's decline counter exactly once.
  #
  # @return [Boolean] true if this call declined the fight, false if it was a no-op
  def decline!
    with_lock do
      return false unless actionable?

      update!(status: :declined)
      opponent.increment!(:declines)
      true
    end
  end

  # Writes one fighter's committed moves. Public so create_challenge! (challenger)
  # and respond! (opponent) share the same validated path.
  #
  # @param fighter [Fighter]
  # @param moves [Array<Hash>]
  def write_moves!(fighter:, moves:)
    normalize_moves(moves).each do |move|
      fight_moves.create!(
        fighter: fighter,
        round: move.fetch(:round),
        attack_height: move.fetch(:attack_height),
        attack_style: move.fetch(:attack_style),
        block_height: move.fetch(:block_height)
      )
    end
  end

  # Inbox view for the opponent: enough to size up the challenge and scout the
  # challenger, with ZERO move data. Belts/records are the challenger's SNAPSHOT
  # so the opponent sees the fight they'd actually be fighting.
  #
  # @return [Hash]
  def inbox_payload
    {
      id: id,
      status: status,
      created_at: created_at,
      expires_at: expires_at,
      challenger: fighter_summary(challenger, belt: challenger_belt),
      opponent: fighter_summary(opponent, belt: opponent_belt)
    }
  end

  # Full playback data, available ONLY once resolved: both movesets, resolved
  # rounds, the outcome, and XP deltas. Nil before resolution so no code path can
  # leak moves early.
  #
  # @return [Hash, nil]
  def playback_payload
    return nil unless resolved?

    last_round = fight_rounds.map(&:round).max
    challenger_base = Belt.base_damage_for(challenger_belt)
    opponent_base = Belt.base_damage_for(opponent_belt)

    {
      id: id,
      ko: ko,
      resolved_at: resolved_at,
      winner_side: winner_side,
      challenger: fighter_summary(challenger, belt: challenger_belt).merge(
        xp_delta: challenger_xp_delta,
        moves: moves_payload(challenger),
        belt_change: belt_change_for(challenger_belt, challenger_xp, challenger_xp_delta)
      ),
      opponent: fighter_summary(opponent, belt: opponent_belt).merge(
        xp_delta: opponent_xp_delta,
        moves: moves_payload(opponent),
        belt_change: belt_change_for(opponent_belt, opponent_xp, opponent_xp_delta)
      ),
      rounds: fight_rounds.map do |r|
        ko_round = ko && r.round == last_round
        {
          round: r.round,
          challenger_damage: r.challenger_damage,
          opponent_damage: r.opponent_damage,
          challenger_hp_after: r.challenger_hp_after,
          opponent_hp_after: r.opponent_hp_after,
          announcer: FightAnnouncer.line(
            seed: id,
            round: r.round,
            challenger_damage: r.challenger_damage,
            opponent_damage: r.opponent_damage,
            challenger_base: challenger_base,
            opponent_base: opponent_base,
            ko: ko_round,
            winner_name: ko_round ? winner&.display_name : nil
          )
        }
      end
    }
  end

  # The moves +fighter+ committed in this fight as compact
  # [attack_height, attack_style, block_height] tuples in round order — the
  # at-a-glance pattern read for scouting tables. Deliberately key-free (no
  # attack_height/block_height names) and EMPTY until resolved, so pending
  # commits stay sealed and payloads never carry the sealed-move vocabulary.
  #
  # @param fighter [Fighter]
  # @return [Array<Array(Integer, Integer, Integer)>]
  def scouting_moves_for(fighter)
    return [] unless resolved?

    fight_moves.select { |m| m.fighter_id == fighter.id }
               .sort_by(&:round)
               .map { |m| [ m.attack_height, m.attack_style, m.block_height ] }
  end

  # @return ["challenger", "opponent", nil] which side won, nil for a draw
  def winner_side
    return nil if winner_id.nil?

    winner_id == challenger_id ? "challenger" : "opponent"
  end

  # @return [Boolean] whether this pending fight is past its response deadline
  def expired_by_time?
    pending? && expires_at.present? && expires_at <= Time.current
  end

  # Whether the challenger has been grinding this exact opponent — {FARM_LIMIT}+
  # fights between the pair inside {FARM_WINDOW}, this pending one excluded. The
  # cue a temperamental bot declines on.
  #
  # @return [Boolean]
  def farmed_by_challenger?
    self.class.between(challenger, opponent)
        .where(created_at: FARM_WINDOW.ago..)
        .where.not(id: id)
        .count >= FARM_LIMIT
  end

  # Compact resolved-fight line for the dojo ticker / recent-fights sidebar. Both
  # sides' name + snapshot belt, who won (nil = draw), whether it was a KO, and a
  # link to the playback. Shared by the initial server render and the live
  # fight_resolved broadcast so both read identically.
  #
  # @return [Hash]
  def ticker_payload
    {
      id: id,
      ko: ko,
      draw: winner_id.nil?,
      winner_side: winner_side,
      resolved_at: resolved_at&.iso8601,
      url: url_helpers.fight_path(self),
      challenger: fighter_summary(challenger, belt: challenger_belt),
      opponent: fighter_summary(opponent, belt: opponent_belt)
    }
  end

  # A pending challenge as the live inbox renders it: the other party's summary
  # (no sealed moves — sized off {inbox_payload}) plus the URLs the card links to.
  #
  # @return [Hash]
  def challenge_card_payload
    inbox_payload.merge(
      respond_url: url_helpers.challenge_path(self),
      challenger_url: url_helpers.fighter_path(challenger),
      opponent_url: url_helpers.fighter_path(opponent)
    )
  end

  private

  def url_helpers
    Rails.application.routes.url_helpers
  end

  # New challenge → notify the opponent's inbox. A challenge is always born
  # pending; the guard keeps factory-built resolved fixtures from announcing a
  # phantom challenge.
  def broadcast_challenge_received
    return unless pending?

    FighterChannel.broadcast_to(opponent, event: "challenge_received", fight: challenge_card_payload)
    PushChallengeNotificationJob.perform_later(id) unless opponent.bot?
  end

  # Status flips drive the rest of the living world. Only fire on an actual status
  # change so unrelated updates (e.g. a lazy expiry touch) stay quiet.
  def broadcast_status_change
    return unless saved_change_to_status?

    if resolved?
      DojoChannel.broadcast_event(event: "fight_resolved", fight: ticker_payload)
      FighterChannel.broadcast_to(challenger, event: "challenge_resolved", fight: ticker_payload)
    elsif declined?
      FighterChannel.broadcast_to(challenger, event: "challenge_declined", fight: challenge_card_payload)
    elsif expired?
      FighterChannel.broadcast_to(challenger, event: "challenge_expired", fight: challenge_card_payload)
    end
  end

  # Whether a pending action (respond/decline) may proceed. Lazily flips a
  # past-expiry pending fight to expired and refuses — no daily job needed to
  # keep stale challenges out of the resolution path.
  def actionable?
    return false unless pending?

    if expires_at <= Time.current
      update!(status: :expired)
      return false
    end

    true
  end

  def persist_result!(result)
    result.rounds.each do |round|
      fight_rounds.create!(
        round: round.round,
        challenger_damage: round.challenger_damage,
        opponent_damage: round.opponent_damage,
        challenger_hp_after: round.challenger_hp_after,
        opponent_hp_after: round.opponent_hp_after
      )
    end

    outcome = outcome_for(result.winner)
    deltas = Xp::Rules.deltas(
      challenger_belt: challenger_belt,
      opponent_belt: opponent_belt,
      outcome: outcome
    )

    update!(
      status: :resolved,
      ko: result.ko,
      resolved_at: Time.current,
      winner_id: winner_id_for(result.winner),
      challenger_xp_delta: deltas[:challenger],
      opponent_xp_delta: deltas[:opponent]
    )

    apply_outcome_to_fighter(challenger, delta: deltas[:challenger], result: result_for(challenger, result.winner))
    apply_outcome_to_fighter(opponent, delta: deltas[:opponent], result: result_for(opponent, result.winner))
  end

  # Lands XP, re-settles the belt with hysteresis, bumps the right counter, and
  # stamps last_fought_at on a real fighter, from that fighter's own snapshot XP.
  def apply_outcome_to_fighter(fighter, delta:, result:)
    fighter.lock!
    new_xp = Xp::Rules.apply(current_xp: fighter.xp, delta: delta, current_belt: fighter.belt)
    fighter.xp = new_xp
    fighter.belt = Belt.settle(current_belt: fighter.belt, xp: new_xp)
    fighter.public_send(:"#{result}=", fighter.public_send(result) + 1)
    fighter.last_fought_at = Time.current
    fighter.save!
  end

  def outcome_for(resolver_winner)
    case resolver_winner
    when :challenger then :challenger_win
    when :opponent then :opponent_win
    else :draw
    end
  end

  def winner_id_for(resolver_winner)
    case resolver_winner
    when :challenger then challenger_id
    when :opponent then opponent_id
    end
  end

  # The counter to bump on +fighter+ given the resolver's winner symbol.
  def result_for(fighter, resolver_winner)
    return :draws if resolver_winner.nil?

    winner = resolver_winner == :challenger ? challenger : opponent
    fighter == winner ? :wins : :losses
  end

  def ordered_moves(fighter)
    fight_moves.where(fighter: fighter).order(:round).to_a
  end

  def moves_payload(fighter)
    ordered_moves(fighter).map do |m|
      { round: m.round, attack_height: m.attack_height, attack_style: m.attack_style, block_height: m.block_height }
    end
  end

  # Whether this fight's XP delta crossed a belt boundary for one side, for the
  # outcome banner's promotion/demotion callout. Derived from the SNAPSHOT belt +
  # XP + delta so it's self-contained and replay-stable (exact in the common case
  # where no other fight settled between challenge and resolution).
  #
  # @return [Hash, nil] { direction:, from_belt:, to_belt:, to_belt_name: } or nil
  def belt_change_for(snapshot_belt, snapshot_xp, delta)
    return nil if delta.nil?

    after = Belt.settle(current_belt: snapshot_belt, xp: snapshot_xp + delta)
    return nil if after == snapshot_belt

    {
      direction: after > snapshot_belt ? "promotion" : "demotion",
      from_belt: snapshot_belt,
      to_belt: after,
      to_belt_name: Belt.name_for(after)
    }
  end

  def fighter_summary(fighter, belt:)
    {
      id: fighter.id,
      name: fighter.name,
      display_name: fighter.display_name,
      belt: belt,
      belt_name: Belt.name_for(belt),
      bot: fighter.bot,
      record: { wins: fighter.wins, losses: fighter.losses, draws: fighter.draws }
    }
  end

  # Coerces move hashes to symbol keys with integer values so callers may pass
  # string-keyed JSON from a form/fetch or symbol-keyed hashes from Ruby.
  def normalize_moves(moves)
    moves.map do |m|
      h = m.respond_to?(:to_unsafe_h) ? m.to_unsafe_h : m
      h = h.symbolize_keys
      {
        round: Integer(h.fetch(:round)),
        attack_height: Integer(h.fetch(:attack_height)),
        attack_style: Integer(h.fetch(:attack_style)),
        block_height: Integer(h.fetch(:block_height))
      }
    end
  end

  def distinct_fighters
    return if challenger.nil? || opponent.nil?

    errors.add(:opponent, "can't be the same fighter as the challenger") if challenger == opponent
  end
end
