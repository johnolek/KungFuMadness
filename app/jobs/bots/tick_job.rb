module Bots
  # The heartbeat of the bot population. Scheduled every minute (config/recurring.yml)
  # and manually runnable in dev via +bin/rails bots:tick+. Each tick, every bot
  # consults its {Persona} and maybe acts — but most bots most ticks do nothing, so
  # with a ~200-bot roster the dojo sees a fight resolve every few minutes rather
  # than a flood (see the persona math in CLAUDE.md).
  #
  # Three things happen, in order, all driven by presence:
  #
  #   1. login / logout — a bot in an active hour may start a session (stamp
  #      last_seen_at, announce online); an online bot may end one (go stale,
  #      announce offline). Presence rides the same {DojoChannel} path humans use,
  #      so a bot logging on is indistinguishable from a person stepping onto the mat.
  #   2. respond — for each pending challenge older than the bot's response delay,
  #      accept via {Brain} or decline per temperament. Only online bots answer;
  #      that's what makes the world feel awake rather than instant.
  #   3. challenge — per its aggression, an online bot picks an online-ish fighter
  #      within +/-2 belts and challenges it, respecting the pair cooldown, the
  #      single-outstanding rule, and a cap on how many pendings pile on one human.
  #
  # Batched queries throughout: the roster and online set load once, pending
  # challenges and per-human pending counts load in one query each, so the tick
  # stays flat over 200 bots with no N+1.
  class TickJob < ApplicationJob
    queue_as :default

    # Belts either side of a bot it's willing to challenge.
    BELT_REACH = 2
    # Most pending challenges allowed to stack on a single human opponent.
    MAX_PENDING_PER_HUMAN = 2

    # @param now [Time] injectable clock (the sim and specs pin it)
    # @param rng [Random] injectable dice source
    def perform(now: Time.current, rng: Random.new)
      @now = now
      @rng = rng

      online = Fighter.bots.each_with_object([]) do |bot, acc|
        persona = Persona.for(bot)
        acc << [ bot, persona ] if update_presence(bot, persona)
      end

      respond_to_challenges(online)
      issue_challenges(online)
    end

    private

    attr_reader :now, :rng

    # Advances one bot's session state and returns whether it's online afterward.
    # Presence is judged against the injected clock, not wall time, so the sim and
    # specs can drive the tick at any point on the timeline.
    def update_presence(bot, persona)
      if online?(bot)
        if !persona.active_now?(now) || persona.wants_to_logout?(rng)
          log_off(bot)
          false
        else
          bot.update_column(:last_seen_at, now)
          true
        end
      elsif persona.active_now?(now) && persona.wants_to_login?(rng)
        log_on(bot)
        true
      else
        false
      end
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

    def respond_to_challenges(online)
      by_id = online.to_h { |bot, persona| [ bot.id, [ bot, persona ] ] }
      return if by_id.empty?

      Fight.pending.where(opponent_id: by_id.keys).includes(:challenger).find_each do |fight|
        bot, persona = by_id[fight.opponent_id]
        age_minutes = (now - fight.created_at) / 60.0
        next unless persona.ready_to_respond?(age_minutes: age_minutes, rng: rng)

        if persona.decline?(my_belt: fight.opponent_belt, challenger_belt: fight.challenger_belt,
                            farming: fight.farmed_by_challenger?, rng: rng)
          fight.decline!
        else
          moves = Brain.moves_for(fighter: bot, opponent: fight.challenger, rng: rng)
          fight.respond!(moves: moves, rng: rng)
        end
      end
    end

    def issue_challenges(online)
      challengers = online.select { |_bot, persona| persona.wants_to_challenge?(rng) }
      return if challengers.empty?

      # Candidate targets: the bots we just saw online plus any human seen online
      # against the same clock. Both prefer live opponents, which keeps the world's
      # activity clustered where people actually are.
      candidates = online.map(&:first) + Fighter.humans.where(last_seen_at: (now - Fighter::ONLINE_WINDOW)..).to_a
      pending_on_human = human_pending_counts

      challengers.each do |bot, _persona|
        target = pick_target(bot, candidates, pending_on_human)
        next unless target

        challenge(bot, target)
        pending_on_human[target.id] += 1 unless target.bot?
      end
    end

    # Picks a fightable opponent for +bot+: within belt reach, not itself, off
    # cooldown, no challenge already outstanding to it, and not over the pending cap
    # if human. Prefers currently-online fighters; that's the whole candidate pool
    # here, which keeps the world's activity clustered where people actually are.
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
      Fight.create_challenge!(challenger: bot, opponent: target, moves: Brain.moves_for(fighter: bot, opponent: target, rng: rng))
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
