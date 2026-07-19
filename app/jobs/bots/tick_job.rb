module Bots
  # The heartbeat of the bot population — a PLANNER, run every minute
  # (config/recurring.yml) and manually runnable in dev via +bin/rails bots:tick+.
  # It does NOT act. Each minute it consults every bot's {Persona} and decides what
  # that bot WANTS to do this minute, then hands each intent to a {ActJob} scheduled
  # at a random second (+wait: rand(0..59).seconds+). Spreading the work is the whole
  # point: with ~20–40 acting bots a minute the dojo dribbles continuously instead of
  # lurching every action out at :00. Most bots most minutes want nothing and get no
  # job at all.
  #
  # What it plans, in order, all driven by presence:
  #
  #   1. login / logout — a bot in an active hour may want to start a session; an
  #      online bot may want to end one. The actual stamp + announce happens in the
  #      ActJob, so presence itself lands at the jittered second (the Online Now
  #      sidebar dribbles too).
  #   2. respond — for each pending challenge older than the opponent bot's response
  #      delay, mark it ready to answer. Only bots that will be online this minute
  #      answer. The accept-vs-decline call and the resolve happen in the ActJob.
  #   3. challenge — per its aggression, an online bot is flagged to go looking for a
  #      fight; the ActJob picks a live target at execution time.
  #
  # Batched queries throughout: the roster loads once and pending challenges load in
  # one query, so planning stays flat over 200 bots with no N+1. The persona RNG
  # rolls happen here (injectable +rng+, so the sim and specs replay deterministically);
  # only the durable per-bot jitter uses Kernel#rand in the enqueue path.
  class TickJob < ApplicationJob
    queue_as :default

    # @param now [Time] injectable clock (the sim and specs pin it)
    # @param rng [Random] injectable dice source for the persona rolls
    # @param inline [Boolean] run each planned ActJob immediately in-process instead
    #   of enqueuing it delayed — the +bots:tick+ rake path, for manual dev poking.
    def perform(now: Time.current, rng: Random.new, inline: false)
      @now = now
      @rng = rng

      online = []
      plans = Fighter.bots.each_with_object({}) do |bot, acc|
        persona = Persona.for(bot)
        presence = plan_presence(bot, persona)
        acc[bot.id] = { presence: presence, respond_fight_ids: [], challenge: false }
        online << [ bot, persona ] if will_be_online?(bot, presence)
      end

      plan_responses(online, plans)
      plan_challenges(online, plans)

      dispatch(plans, inline: inline)
    end

    private

    attr_reader :now, :rng

    # What presence change, if any, this bot wants this minute. Judged against the
    # injected clock so the sim and specs can drive the tick anywhere on the timeline.
    #
    # @return [Symbol, nil] :login, :logout, or nil
    def plan_presence(bot, persona)
      if online?(bot)
        :logout if !persona.active_now?(now) || persona.wants_to_logout?(rng)
      elsif persona.active_now?(now) && persona.wants_to_login?(rng)
        :login
      end
    end

    # Whether the bot will be online this minute given its planned presence — the
    # set that's eligible to respond and challenge.
    def will_be_online?(bot, presence)
      case presence
      when :login then true
      when :logout then false
      else online?(bot)
      end
    end

    def plan_responses(online, plans)
      by_id = online.to_h { |bot, persona| [ bot.id, [ bot, persona ] ] }
      return if by_id.empty?

      Fight.pending.where(opponent_id: by_id.keys).find_each do |fight|
        _bot, persona = by_id[fight.opponent_id]
        age_minutes = (now - fight.created_at) / 60.0
        next unless persona.ready_to_respond?(age_minutes: age_minutes, rng: rng)

        plans[fight.opponent_id][:respond_fight_ids] << fight.id
      end
    end

    def plan_challenges(online, plans)
      online.each do |bot, persona|
        plans[bot.id][:challenge] = true if persona.wants_to_challenge?(rng)
      end
    end

    # Hands each non-empty plan to an ActJob. Durable delayed jobs via Solid Queue —
    # not in-memory scheduling — so the jitter survives restarts and works across the
    # forked workers. The wait uses Kernel#rand (not the injected rng), keeping the
    # spread out of the deterministic persona rolls.
    def dispatch(plans, inline:)
      plans.each do |bot_id, plan|
        next unless plan[:presence] || plan[:respond_fight_ids].any? || plan[:challenge]

        hints = {
          presence: plan[:presence]&.to_s,
          respond_fight_ids: plan[:respond_fight_ids],
          challenge: plan[:challenge]
        }

        if inline
          ActJob.new.perform(bot_id, now: now, **hints)
        else
          ActJob.set(wait: rand(0..59).seconds).perform_later(bot_id, **hints)
        end
      end
    end

    def online?(bot)
      bot.last_seen_at.present? && bot.last_seen_at >= now - Fighter::ONLINE_WINDOW
    end
  end
end
