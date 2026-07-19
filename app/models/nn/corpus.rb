module Nn
  # Builds the supervised training set for the move-prediction brains. Each labelled
  # example is: the UNMASKED feature vector describing a fighter from their history
  # so far, paired with the attack/block height they actually threw next. The
  # trainer masks these per tier; here we only produce the raw signal.
  #
  # Two sources, same shape:
  #   * {generate} — heuristic bots (from {Bots::Roster}) fought in memory, seeded,
  #     no DB. This is the ecology's move behaviour turned into prediction targets.
  #   * {from_database} — every real resolved fight, replayed oldest-first so each
  #     fighter's history accumulates exactly as it did in the world.
  #
  # In both cases a fighter's Nth fight yields three samples (one per round) built
  # from their first N-1 fights, so the temporal ordering is honest.
  module Corpus
    # One labelled example. +input+ is the full {Features::SIZE} unmasked vector;
    # +attack+/+block+ are zero-based height labels (0=low, 1=mid, 2=high).
    Sample = Data.define(:input, :attack, :block)

    HISTORY_LIMIT = Features::HISTORY_LIMIT
    BELT_REACH = 2

    module_function

    # @param fights [Integer] number of simulated fights to play
    # @param roster_size [Integer] heuristic bots to draw from {Bots::Roster}
    # @param seed [Integer] deterministic RNG + roster seed
    # @return [Array<Sample>]
    def generate(fights: 4000, roster_size: 120, seed: 1)
      rng = Random.new(seed)
      bots = Bots::Roster.generate(target: roster_size, seed: seed).each_with_index.map do |spec, i|
        SimBot.new(id: i, belt: spec[:belt], strategy: spec[:strategy].deep_stringify_keys)
      end
      histories = Hash.new { |h, k| h[k] = [] }
      samples = []

      fights.times do
        a, b = pick_pair(bots, rng)
        next unless a

        play_fight(a, b, histories, samples, rng)
      end

      samples
    end

    # @return [Array<Sample>] samples drawn from real resolved fights (may be empty)
    def from_database
      histories = Hash.new { |h, k| h[k] = [] }
      samples = []

      Fight.resolved.includes(:fight_moves).order(:resolved_at, :id).find_each do |fight|
        record_fight_samples(fight, histories, samples)
      end

      samples
    end

    # A minimal heuristic bot for corpus play: enough for {Bots::Brain} to pick
    # moves and to scout by belt. It carries no fight history, so any "nn" strategy
    # cleanly falls back to biased sampling here (it cannot recurse into itself).
    SimBot = Struct.new(:id, :belt, :strategy, keyword_init: true)

    def pick_pair(bots, rng)
      a = bots.sample(random: rng)
      candidates = bots.select { |o| o.id != a.id && (o.belt - a.belt).abs <= BELT_REACH }
      b = candidates.sample(random: rng)
      b ? [ a, b ] : [ nil, nil ]
    end

    # Records both fighters' samples from their PRE-fight history, resolves the
    # fight for the win/form signal, then appends the new fight to each history.
    def play_fight(a, b, histories, samples, rng)
      a_moves = Bots::Brain.moves_for(fighter: a, opponent: b, rng: rng)
      b_moves = Bots::Brain.moves_for(fighter: b, opponent: a, rng: rng)

      result = FightResolver.new(
        challenger_moves: a_moves, opponent_moves: b_moves,
        challenger_belt: a.belt, opponent_belt: b.belt, rng: rng
      ).resolve
      a_won = result.winner == :challenger
      b_won = result.winner == :opponent

      append_samples(samples, histories[a.id], a_moves, belt_gap: a.belt - b.belt)
      append_samples(samples, histories[b.id], b_moves, belt_gap: b.belt - a.belt)

      histories[a.id].unshift(sample_from_moves(a_moves, a_won)).slice!(HISTORY_LIMIT..)
      histories[b.id].unshift(sample_from_moves(b_moves, b_won)).slice!(HISTORY_LIMIT..)
    end

    def record_fight_samples(fight, histories, samples)
      [ fight.challenger, fight.opponent ].each do |fighter|
        other = fighter == fight.challenger ? fight.opponent : fight.challenger
        belt = fighter == fight.challenger ? fight.challenger_belt : fight.opponent_belt
        other_belt = fighter == fight.challenger ? fight.opponent_belt : fight.challenger_belt
        moves = fight.fight_moves.select { |m| m.fighter_id == fighter.id }.sort_by(&:round)
        next if moves.size < Features::ROUNDS

        append_samples(samples, histories[fighter.id], move_hashes(moves), belt_gap: belt - other_belt)
        histories[fighter.id].unshift(
          Features::Sample.new(
            attack_heights: moves.map(&:attack_height),
            block_heights: moves.map(&:block_height),
            won: fight.winner_id == fighter.id
          )
        ).slice!(HISTORY_LIMIT..)
      end
    end

    def append_samples(samples, history, moves, belt_gap:)
      (1..Features::ROUNDS).each do |round|
        move = moves[round - 1]
        input = Features.build(history: history, round: round, belt_gap: belt_gap, mask: Features::MASKS["master"])
        samples << Sample.new(input: input, attack: move[:attack_height] - 1, block: move[:block_height] - 1)
      end
    end

    def sample_from_moves(moves, won)
      Features::Sample.new(
        attack_heights: moves.map { |m| m[:attack_height] },
        block_heights: moves.map { |m| m[:block_height] },
        won: won
      )
    end

    def move_hashes(moves)
      moves.map { |m| { round: m.round, attack_height: m.attack_height, block_height: m.block_height } }
    end
  end
end
