module Bots
  # Turns a bot's stored strategy config into three rounds of committed moves.
  # Two heuristic strategies ship in Phase 2:
  #
  #   pattern — a fixed, fully-scoutable loop of moves cycled across the rounds.
  #   biased  — weighted sampling of attack/block heights with an epsilon of pure
  #             randomness so the bot isn't perfectly predictable.
  #
  # +adaptive+ (best-responding to an opponent's scouted tendencies) is a later
  # phase; encountering it here falls back to biased defaults.
  #
  # The RNG is injectable so specs and the balance sim stay deterministic.
  module Brain
    ROUNDS = FightResolver::ROUNDS
    HEIGHTS = FightMove::HEIGHTS.values.freeze # [1, 2, 3]
    STYLES = FightMove::STYLES.values.freeze   # [0, 1]
    # Maps the human height names used in strategy config to stored integers.
    HEIGHT_BY_NAME = FightMove::HEIGHTS.transform_keys(&:to_s).freeze
    DEFAULT_EPSILON = 0.1

    module_function

    # @param fighter [Fighter] the bot choosing moves
    # @param opponent [Fighter] the other fighter (unused until adaptive brains)
    # @param rng [Random] injectable dice source
    # @return [Array<Hash>] three rounds of { round:, attack_height:, attack_style:, block_height: }
    def moves_for(fighter:, opponent:, rng: Random.new)
      strategy = (fighter.strategy || {}).with_indifferent_access
      case strategy[:type]
      when "pattern" then pattern_moves(strategy, rng)
      else biased_moves(strategy, rng)
      end
    end

    # Cycles the configured loop across the three rounds. A missing/empty loop
    # degrades to biased defaults so a misconfigured bot still fights.
    def pattern_moves(strategy, rng)
      loop_moves = Array(strategy[:loop])
      return biased_moves(strategy, rng) if loop_moves.empty?

      (1..ROUNDS).map do |round|
        spec = loop_moves[(round - 1) % loop_moves.size].with_indifferent_access
        {
          round: round,
          attack_height: height_from(spec[:attack_height]),
          attack_style: (spec[:attack_style] || STYLES.sample(random: rng)).to_i,
          block_height: height_from(spec[:block_height])
        }
      end
    end

    # Samples each height from the configured weights, with an epsilon chance of a
    # uniformly random height instead. Style is coin-flipped (aesthetic only).
    def biased_moves(strategy, rng)
      epsilon = (strategy[:epsilon] || DEFAULT_EPSILON).to_f
      attack_weights = weight_map(strategy[:attack_weights])
      block_weights = weight_map(strategy[:block_weights])

      (1..ROUNDS).map do |round|
        {
          round: round,
          attack_height: sample_height(attack_weights, epsilon, rng),
          attack_style: STYLES.sample(random: rng),
          block_height: sample_height(block_weights, epsilon, rng)
        }
      end
    end

    # @return [Integer] a height in 1..3
    def sample_height(weights, epsilon, rng)
      return HEIGHTS.sample(random: rng) if rng.rand < epsilon

      weighted_pick(weights, rng)
    end

    # Weighted choice over {height => weight}; falls back to uniform when empty.
    def weighted_pick(weights, rng)
      total = weights.values.sum
      return HEIGHTS.sample(random: rng) if total <= 0

      roll = rng.rand * total
      cumulative = 0.0
      weights.each do |height, weight|
        cumulative += weight
        return height if roll < cumulative
      end
      weights.keys.last
    end

    # Normalizes a weight config ({ "low" => 2, ... } or { "1" => 2 }) to a
    # {1 => w, 2 => w, 3 => w} map, defaulting to uniform when absent.
    def weight_map(config)
      return HEIGHTS.to_h { |h| [ h, 1.0 ] } if config.blank?

      HEIGHTS.to_h do |height|
        name = HEIGHT_BY_NAME.key(height)
        weight = config[name] || config[height.to_s] || config[height] || 0
        [ height, weight.to_f ]
      end
    end

    def height_from(value)
      return value.to_i if value.is_a?(Integer) || value.to_s.match?(/\A\d+\z/)

      HEIGHT_BY_NAME.fetch(value.to_s, 2)
    end
  end
end
