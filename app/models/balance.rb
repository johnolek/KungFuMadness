# Random-play win-rate sweep used to keep the belt curves honest. Both fighters
# throw uniformly random moves through {FightResolver}, so the only thing under
# test is the HP/damage math in {Belt}. Deterministic given a seed. Drives both
# +bin/rails balance:simulate+ and the envelope spec.
module Balance
  # A gap's aggregated outcome over many random fights. All rates are fractions of
  # the sample except +higher_decisive_win_rate+, which excludes draws.
  Row = Data.define(:challenger_belt, :opponent_belt, :gap, :fights,
                    :higher_win_rate, :lower_win_rate, :draw_rate, :ko_rate,
                    :avg_rounds, :higher_decisive_win_rate)

  # Belt pairs swept by default: gap 0..4 up from white, plus two mid-ladder
  # pairs to catch the nonlinearity a fixed HP/damage step introduces higher up.
  DEFAULT_PAIRS = [ [ 1, 1 ], [ 1, 2 ], [ 1, 3 ], [ 1, 4 ], [ 1, 5 ], [ 4, 5 ], [ 4, 6 ] ].freeze

  module_function

  # Run +fights+ random fights for the given belt pair (opponent is the higher or
  # equal belt) and aggregate the result.
  #
  # @param challenger_belt [Integer]
  # @param opponent_belt [Integer]
  # @param fights [Integer]
  # @param rng [Random]
  # @return [Row]
  def run_pair(challenger_belt:, opponent_belt:, fights:, rng: Random.new)
    higher_wins = lower_wins = draws = kos = 0
    rounds_total = 0

    fights.times do
      result = FightResolver.new(
        challenger_moves: random_moves(rng),
        opponent_moves: random_moves(rng),
        challenger_belt: challenger_belt,
        opponent_belt: opponent_belt,
        rng: rng
      ).resolve

      rounds_total += result.rounds.size
      kos += 1 if result.ko

      case result.winner
      when nil then draws += 1
      when :opponent then higher_wins += 1
      when :challenger then lower_wins += 1
      end
    end

    decisive = higher_wins + lower_wins

    Row.new(
      challenger_belt: challenger_belt,
      opponent_belt: opponent_belt,
      gap: opponent_belt - challenger_belt,
      fights: fights,
      higher_win_rate: higher_wins.to_f / fights,
      lower_win_rate: lower_wins.to_f / fights,
      draw_rate: draws.to_f / fights,
      ko_rate: kos.to_f / fights,
      avg_rounds: rounds_total.to_f / fights,
      higher_decisive_win_rate: decisive.zero? ? 0.0 : higher_wins.to_f / decisive
    )
  end

  # @param pairs [Array<Array(Integer,Integer)>]
  # @param fights [Integer]
  # @param seed [Integer] a single seed threads the whole sweep for determinism
  # @return [Array<Row>]
  def sweep(pairs: DEFAULT_PAIRS, fights: 5000, seed: 1)
    rng = Random.new(seed)
    pairs.map do |challenger_belt, opponent_belt|
      run_pair(challenger_belt: challenger_belt, opponent_belt: opponent_belt, fights: fights, rng: rng)
    end
  end

  # @param rng [Random]
  # @return [Array<Hash>] three rounds of uniformly random committed moves
  def random_moves(rng)
    Array.new(FightResolver::ROUNDS) do
      { attack_height: rng.rand(1..3), block_height: rng.rand(1..3), attack_style: rng.rand(0..1) }
    end
  end
end
