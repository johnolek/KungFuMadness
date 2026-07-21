module Bots
  # One bot's turn, executed at a jittered second within the minute. {TickJob} is
  # the planner — every minute it decides which bots WANT to act and enqueues an
  # ActJob per bot with +wait: rand(0..59).seconds+, so the world dribbles out
  # continuously instead of firing every action at :00.
  #
  # ActJob RE-EVALUATES at execution time, because up to a minute has passed since
  # the plan: the bot may have logged off, a pending challenge may have resolved or
  # expired, a cooldown may have started. So every action re-reads current state
  # and leans on the same locked, pending-guarded paths ({Fight#respond!},
  # {Fight#decline!}, {Fight.create_challenge!}) that already tolerate races — which
  # makes a duplicate or stale ActJob a clean no-op.
  #
  # The hints are intent, not commands:
  #   presence          — "login" / "logout" / nil (applied only if still warranted)
  #   respond_fight_ids — challenges the planner judged ready to answer (each is
  #                       re-checked for still being pending before we touch it)
  #   challenge         — whether to go looking for a fight (target picked live)
  class ActJob < ApplicationJob
    queue_as :default

    # Belts either side of a bot it's willing to challenge.
    BELT_REACH = 2
    # Most pending challenges allowed to stack on a single human opponent.
    MAX_PENDING_PER_HUMAN = 6

    # @param bot_id [Integer]
    # @param presence [String, nil] "login" | "logout" | nil
    # @param respond_fight_ids [Array<Integer>] challenges the planner deemed ready
    # @param challenge [Boolean] whether this bot means to issue a challenge
    # @param now [Time] injectable clock (defaults to execution time — the point)
    # @param rng [Random] injectable dice source
    def perform(bot_id, presence: nil, respond_fight_ids: [], challenge: false,
                now: Time.current, rng: Random.new)
      @now = now
      @rng = rng

      bot = Fighter.bots.find_by(id: bot_id)
      return unless bot

      apply_presence(bot, presence)
      respond(bot, respond_fight_ids)
      issue_challenge(bot) if challenge
    end

    private

    attr_reader :now, :rng

    # Carry out the planned presence change only if it still applies: a "login"
    # that already happened, or a "logout" for a bot that already went stale, is a
    # no-op — no duplicate online/offline broadcast.
    def apply_presence(bot, presence)
      case presence.to_s
      when "login"
        log_on(bot) unless online?(bot)
      when "logout"
        log_off(bot) if online?(bot)
      end
    end

    # Answer the challenges the planner flagged, re-checking each is still pending
    # (it may have resolved or expired since planning). Answering is itself an act
    # of presence, so the bot's clock is refreshed the way {RespondJob} does it.
    def respond(bot, fight_ids)
      return if Array(fight_ids).empty?

      bot.update_column(:last_seen_at, now)

      Fight.pending.where(id: fight_ids, opponent_id: bot.id).includes(:challenger).find_each do |fight|
        persona = Persona.for(bot)
        if persona.decline?(my_belt: fight.opponent_belt, challenger_belt: fight.challenger_belt,
                            farming: fight.farmed_by_challenger?, rng: rng)
          fight.decline!
        else
          moves = Brain.moves_for(fighter: bot, opponent: fight.challenger, rng: rng)
          fight.respond!(moves: moves, rng: rng)
        end
      end
    end

    # Pick a live opponent and open a challenge. Candidates are re-queried NOW, so
    # the pool reflects who is actually online at this jittered moment, and the
    # per-human pending cap is enforced against current counts. Humans who turned
    # bot challenges off never enter the pool.
    def issue_challenge(bot)
      bot.update_column(:last_seen_at, now)

      candidates = Fighter.where(last_seen_at: (now - Fighter::ONLINE_WINDOW)..)
                          .where.not(id: bot.id)
                          .accepting_bot_challenges
                          .to_a
      target = pick_target(bot, candidates, human_pending_counts)
      return unless target

      challenge(bot, target)
    end

    def log_on(bot)
      bot.update_column(:last_seen_at, now)
      DojoChannel.broadcast_presence(bot, online: true)
    end

    # Push last_seen_at just outside the online window so the DB agrees the bot is
    # gone the instant we announce it, rather than lingering online for two minutes.
    def log_off(bot)
      bot.update_column(:last_seen_at, now - Fighter::ONLINE_WINDOW - 1.second)
      DojoChannel.broadcast_presence(bot, online: false)
    end

    # Picks a fightable opponent for +bot+: within belt reach, not itself, off
    # cooldown, no challenge already outstanding to it, and not over the pending cap
    # if human.
    def pick_target(bot, candidates, pending_on_human)
      reachable = candidates.select do |other|
        other.id != bot.id &&
          (other.belt - bot.belt).abs <= BELT_REACH &&
          (other.bot? || pending_on_human.fetch(other.id, 0) < MAX_PENDING_PER_HUMAN)
      end
      return if reachable.empty?

      reachable.shuffle(random: rng).find { |other| challengeable?(bot, other) }
    end

    # The game-rule gate the challenge itself would enforce, checked up front so we
    # don't lean on rescuing {Fight::ChallengeError} in the hot path.
    def challengeable?(bot, other)
      return false if Fight.pending.exists?(challenger: bot, opponent: other)

      !Fight.between(bot, other).where(created_at: Fight::CHALLENGE_COOLDOWN.ago..).exists?
    end

    def challenge(bot, target)
      Fight.create_challenge!(challenger: bot, opponent: target,
                              moves: Brain.moves_for(fighter: bot, opponent: target, rng: rng))
    rescue Fight::ChallengeError
      # Lost a race on cooldown/outstanding between the check and the create — fine.
    end

    def online?(bot)
      bot.last_seen_at.present? && bot.last_seen_at >= now - Fighter::ONLINE_WINDOW
    end

    # One query: how many pending challenges currently sit on each human, so the
    # stacking cap needs no per-target count.
    def human_pending_counts
      Fight.pending
           .where(opponent_id: Fighter.humans.select(:id))
           .group(:opponent_id)
           .count
           .tap { |h| h.default = 0 }
    end
  end
end
