module Bots
  # Turns a bot's stored strategy config into three rounds of committed moves.
  # Two heuristic strategies ship in Phase 2:
  #
  #   pattern — a fixed, fully-scoutable loop of moves cycled across the rounds.
  #   biased  — weighted sampling of attack/block heights with an epsilon of pure
  #             randomness so the bot isn't perfectly predictable.
  #
  # +nn+ loads a trained {Brain} (a versioned {Nn::Mlp}), predicts what the OPPONENT
  # will do from their resolved history, and best-responds. +adaptive+ has no
  # dedicated path yet; both fall back to biased sampling when a brain or the
  # opponent's history isn't available — so seeds work with an empty brains table.
  #
  # The RNG is injectable so specs and the balance sim stay deterministic.
  module Brain
    ROUNDS = FightResolver::ROUNDS
    HEIGHTS = FightMove::HEIGHTS.values.freeze # [1, 2, 3]
    STYLES = FightMove::STYLES.values.freeze   # [0, 1]
    # Maps the human height names used in strategy config to stored integers.
    HEIGHT_BY_NAME = FightMove::HEIGHTS.transform_keys(&:to_s).freeze
    DEFAULT_EPSILON = 0.1
    DEFAULT_BRAIN = "master"

    module_function

    # @param fighter [Fighter] the bot choosing moves
    # @param opponent [Fighter] the fighter being scouted (nn best-responds to them)
    # @param rng [Random] injectable dice source
    # @return [Array<Hash>] three rounds of { round:, attack_height:, attack_style:, block_height: }
    def moves_for(fighter:, opponent:, rng: Random.new)
      strategy = (fighter.strategy || {}).with_indifferent_access
      case strategy[:type]
      when "pattern" then pattern_moves(strategy, rng)
      when "nn" then nn_moves(fighter: fighter, opponent: opponent, strategy: strategy, rng: rng)
      else biased_moves(strategy, rng)
      end
    end

    # Predicts the opponent's per-round attack/block distributions with the trained
    # net and best-responds: block their most-likely attack height, attack the
    # height they're least likely to block, with an epsilon of uniform noise.
    #
    # Falls back to biased sampling (using the strategy's own weights) whenever the
    # opponent can't be scouted from a persisted history — e.g. an in-memory sim
    # fighter — or the named brain hasn't been trained yet. The history check runs
    # first so the DB is never touched on the fallback path.
    def nn_moves(fighter:, opponent:, strategy:, rng:)
      history = opponent_history(opponent)
      return biased_moves(strategy, rng) if history.nil?

      brain = ::Brain.cached_latest(strategy[:brain] || DEFAULT_BRAIN)
      return biased_moves(strategy, rng) if brain.nil?

      mlp = brain.mlp
      mask = brain.mask
      epsilon = (strategy[:epsilon] || DEFAULT_EPSILON).to_f
      belt_gap = opponent.belt - fighter.belt

      (1..ROUNDS).map do |round|
        input = Nn::Features.build(history: history, round: round, belt_gap: belt_gap, mask: mask)
        prediction = mlp.forward(input)
        {
          round: round,
          attack_height: best_response(prediction[:block], :min, epsilon, rng),
          attack_style: STYLES.sample(random: rng),
          block_height: best_response(prediction[:attack], :max, epsilon, rng)
        }
      end
    end

    # Scouted fighter's recent resolved fights as {Nn::Features} samples, newest
    # first. Returns nil when the fighter can't supply a resolved history (so the
    # caller falls back instead of predicting from nothing).
    #
    # Structurally sealed-move safe: only {Fighter#resolved_fights} feeds this, so a
    # pending fight's committed moves can never reach the net.
    def opponent_history(opponent)
      return nil unless opponent.respond_to?(:resolved_fights)

      fights = opponent.resolved_fights.limit(Nn::Features::HISTORY_LIMIT).includes(:fight_moves).to_a
      Nn::Features.samples_from_fights(fighter: opponent, fights: fights)
    end

    # @param distribution [Array<Float>] predicted probabilities over heights 1..3
    # @param mode [:max, :min] pick the most- or least-likely height
    # @return [Integer] chosen height (1..3), uniformly random with prob epsilon
    def best_response(distribution, mode, epsilon, rng)
      return HEIGHTS.sample(random: rng) if rng.rand < epsilon

      idx = mode == :max ? argmax(distribution) : argmin(distribution)
      idx + 1
    end

    def argmax(vector)
      vector.each_index.max_by { |i| vector[i] }
    end

    def argmin(vector)
      vector.each_index.min_by { |i| vector[i] }
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
