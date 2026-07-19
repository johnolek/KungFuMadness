module Bots
  # Interprets the +persona+ section of a bot's +strategy+ jsonb into the handful
  # of decisions the per-minute {TickJob} asks of it: when to log on and off, when
  # to fire off a challenge, and how it feels about answering the challenges in its
  # inbox. A persona is pure policy — it holds no fighter state and touches no
  # database; it just turns config + an injectable RNG into yes/no calls, so the
  # tick and the ecology sim can drive it identically and deterministically.
  #
  # Config shape (all keys optional; sane defaults fill the gaps):
  #
  #   persona: {
  #     activity: [[13, 17], [19, 23]],   # UTC hour ranges the bot tends to be on
  #     session_chance: 0.04,             # P(log in) per active-hour tick while offline
  #     session_minutes: [15, 45],        # session length band → per-tick logoff odds
  #     aggression: 0.02,                 # P(issue a challenge) per online tick
  #     decline_style: "grudging",        # meek | proud | grudging
  #     response_delay_minutes: [1, 8]    # how long a challenge sits before an answer
  #   }
  class Persona
    DECLINE_STYLES = %w[meek proud grudging].freeze

    DEFAULTS = {
      "activity" => [ [ 0, 23 ] ],
      "session_chance" => 0.04,
      "session_minutes" => [ 15, 45 ],
      "aggression" => 0.02,
      "decline_style" => "grudging",
      "response_delay_minutes" => [ 1, 8 ]
    }.freeze

    # A belt gap (challenger − me) at or beyond which a "meek" bot ducks a much
    # stronger challenger, and a "proud" bot refuses to stoop to a much weaker one.
    MEEK_FEAR_GAP = 3
    PROUD_SNUB_GAP = -3
    # A "grudging" bot only ever declines outright farming, and even then not always.
    GRUDGING_DECLINE_CHANCE = 0.6

    attr_reader :config

    # @param fighter [Fighter]
    # @return [Persona]
    def self.for(fighter)
      new((fighter.strategy || {})["persona"])
    end

    # @param config [Hash, nil] the persona slice of a bot's strategy
    def initialize(config)
      @config = DEFAULTS.merge((config || {}).stringify_keys) { |_k, default, given| given.nil? ? default : given }
    end

    # Whether the given UTC time falls inside one of the bot's activity windows.
    # Ranges are inclusive hour bounds and may wrap past midnight (e.g. [22, 2]).
    #
    # @param time [Time]
    # @return [Boolean]
    def active_now?(time)
      hour = time.utc.hour
      activity_windows.any? { |from, to| in_window?(hour, from, to) }
    end

    # An offline bot in an active hour decides to start a session.
    # @param rng [Random]
    def wants_to_login?(rng)
      rng.rand < session_chance
    end

    # An online bot decides to end its session this tick. Odds are set so session
    # length is geometric with mean {#avg_session_minutes}, matching the config band.
    # @param rng [Random]
    def wants_to_logout?(rng)
      rng.rand < logout_chance
    end

    # An online bot decides to go looking for a fight this tick.
    # @param rng [Random]
    def wants_to_challenge?(rng)
      rng.rand < aggression
    end

    # Whether a pending challenge that's been waiting +age_minutes+ is old enough to
    # answer. Past the top of the delay band it's always ready; inside the band it
    # becomes ready on a coin-flip so answers spread out instead of arriving in a
    # lump the instant the minimum elapses.
    #
    # @param age_minutes [Float]
    # @param rng [Random]
    # @return [Boolean]
    def ready_to_respond?(age_minutes:, rng:)
      low, high = response_delay_band
      return false if age_minutes < low
      return true if age_minutes >= high

      rng.rand < 0.5
    end

    # Whether this bot declines a challenge rather than fighting it, per temperament:
    #
    #   meek     — ducks anyone {MEEK_FEAR_GAP}+ belts above it (plus farmers)
    #   proud    — snubs anyone {PROUD_SNUB_GAP}+ belts below it, and all farmers
    #   grudging — almost always fights; only sometimes declines outright farming
    #
    # @param my_belt [Integer] the bot's snapshot belt in the challenge
    # @param challenger_belt [Integer] the challenger's snapshot belt
    # @param farming [Boolean] whether the challenger has been farming this bot
    # @param rng [Random]
    # @return [Boolean]
    def decline?(my_belt:, challenger_belt:, farming:, rng:)
      gap = challenger_belt - my_belt

      case decline_style
      when "meek"
        return true if gap >= MEEK_FEAR_GAP

        farming
      when "proud"
        return true if gap <= PROUD_SNUB_GAP

        farming
      else # grudging (and any unknown style)
        farming && rng.rand < GRUDGING_DECLINE_CHANCE
      end
    end

    # @return [Float] mean session length the config band implies
    def avg_session_minutes
      low, high = session_minutes_band
      (low + high) / 2.0
    end

    def decline_style
      style = config["decline_style"].to_s
      DECLINE_STYLES.include?(style) ? style : "grudging"
    end

    private

    def activity_windows
      Array(config["activity"]).map { |w| Array(w).map(&:to_i) }.select { |w| w.size == 2 }
    end

    def in_window?(hour, from, to)
      from <= to ? hour >= from && hour <= to : hour >= from || hour <= to
    end

    def session_chance
      config["session_chance"].to_f
    end

    def aggression
      config["aggression"].to_f
    end

    def logout_chance
      avg = avg_session_minutes
      avg <= 1 ? 1.0 : 1.0 / avg
    end

    def session_minutes_band
      band(config["session_minutes"], DEFAULTS["session_minutes"])
    end

    def response_delay_band
      band(config["response_delay_minutes"], DEFAULTS["response_delay_minutes"])
    end

    def band(value, fallback)
      pair = Array(value).map(&:to_f)
      pair = fallback.map(&:to_f) unless pair.size == 2
      pair.sort
    end
  end
end
