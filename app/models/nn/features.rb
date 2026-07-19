module Nn
  # Builds the fixed-length input vector the {Mlp} reads to predict ONE fighter's
  # moves for a single round — the fighter we are scouting (from a bot's point of
  # view, its opponent). Every feature is derived from that fighter's RESOLVED
  # fight history, never from any pending/committed move, so the sealed-move rule
  # holds structurally.
  #
  # Tiers differ ONLY by which feature GROUPS are visible (see {MASKS}). A hidden
  # group is zeroed rather than removed, so the input size is constant across tiers
  # and one architecture serves every belt.
  #
  # Layout (indices into the 24-dim vector):
  #   [0..2]   round_index   one-hot of the current round (1..3)
  #   [3]      belt_gap      (scouted.belt - viewer.belt) / BELT_GAP_SCALE, clamped
  #   [4..9]   last_fight    one-hot attack height + one-hot block height the fighter
  #                          threw at THIS round index in their single latest fight
  #   [10..15] overall_freq  attack-height freqs (3) + block-height freqs (3), all
  #                          rounds pooled across the history window
  #   [16..21] round_freq    attack-height freqs (3) + block-height freqs (3) at THIS
  #                          round index across the history window
  #   [22..23] form          recent win rate, history depth (samples / HISTORY_LIMIT)
  module Features
    ROUNDS = 3
    HEIGHTS = [ 1, 2, 3 ].freeze
    SIZE = 24
    HISTORY_LIMIT = 8
    BELT_GAP_SCALE = 4.0

    # Contiguous index range of each feature group inside the input vector.
    GROUPS = {
      round_index: 0..2,
      belt_gap: 3..3,
      last_fight: 4..9,
      overall_freq: 10..15,
      round_freq: 16..21,
      form: 22..23
    }.freeze

    # Which groups each tier's brain may see. Low belts scout almost nothing; mid
    # belts remember the last encounter; masters read deep tendencies and form.
    MASKS = {
      "novice" => %i[round_index belt_gap],
      "student" => %i[round_index belt_gap last_fight],
      "master" => %i[round_index belt_gap last_fight overall_freq round_freq form]
    }.freeze

    # One resolved fight from the scouted fighter's perspective, newest-first in a
    # history array. +attack_heights+/+block_heights+ are 3-element arrays (rounds
    # 1..3) of heights 1/2/3; +won+ records whether that fighter won.
    Sample = Data.define(:attack_heights, :block_heights, :won)

    module_function

    # @param history [Array<Sample>] the scouted fighter's recent fights, newest first
    # @param round [Integer] the round being predicted (1..3)
    # @param belt_gap [Integer] scouted fighter's belt minus the viewer's belt
    # @param mask [Array<Symbol>] visible feature groups (defaults to everything)
    # @return [Array<Float>] the SIZE-length input vector, hidden groups zeroed
    def build(history:, round:, belt_gap:, mask: MASKS["master"])
      vector = Array.new(SIZE, 0.0)

      write_round_index(vector, round)
      vector[GROUPS[:belt_gap].first] = (belt_gap / BELT_GAP_SCALE).clamp(-1.0, 1.0)
      write_last_fight(vector, history, round)
      write_frequencies(vector, GROUPS[:overall_freq], pooled_counts(history))
      write_frequencies(vector, GROUPS[:round_freq], round_counts(history, round))
      write_form(vector, history)

      apply_mask(vector, mask)
    end

    # Zeroes every group not in +mask+, returning a copy.
    #
    # @param vector [Array<Float>]
    # @param mask [Array<Symbol>]
    # @return [Array<Float>]
    def apply_mask(vector, mask)
      visible = mask.to_set
      masked = vector.dup
      GROUPS.each do |group, range|
        next if visible.include?(group)

        range.each { |i| masked[i] = 0.0 }
      end
      masked
    end

    # Turns a fighter's resolved Fight records into newest-first history samples.
    #
    # @param fighter [Fighter] the scouted fighter
    # @param fights [Array<Fight>] their resolved fights, newest first
    # @return [Array<Sample>]
    def samples_from_fights(fighter:, fights:)
      fights.map do |fight|
        moves = fight.fight_moves.select { |m| m.fighter_id == fighter.id }.sort_by(&:round)
        Sample.new(
          attack_heights: moves.map(&:attack_height),
          block_heights: moves.map(&:block_height),
          won: fight.winner_id == fighter.id
        )
      end
    end

    def write_round_index(vector, round)
      idx = (round - 1).clamp(0, ROUNDS - 1)
      vector[GROUPS[:round_index].first + idx] = 1.0
    end

    def write_last_fight(vector, history, round)
      last = history.first
      return if last.nil?

      base = GROUPS[:last_fight].first
      attack = last.attack_heights[round - 1]
      block = last.block_heights[round - 1]
      vector[base + (attack - 1)] = 1.0 if attack
      vector[base + 3 + (block - 1)] = 1.0 if block
    end

    def write_frequencies(vector, range, counts)
      attack_total = counts[:attack].sum
      block_total = counts[:block].sum
      base = range.first
      HEIGHTS.each_with_index do |_height, i|
        vector[base + i] = attack_total.zero? ? 0.0 : counts[:attack][i].to_f / attack_total
        vector[base + 3 + i] = block_total.zero? ? 0.0 : counts[:block][i].to_f / block_total
      end
    end

    def write_form(vector, history)
      base = GROUPS[:form].first
      return if history.empty?

      wins = history.count(&:won)
      vector[base] = wins.to_f / history.size
      vector[base + 1] = [ history.size.to_f / HISTORY_LIMIT, 1.0 ].min
    end

    # Height counts over every round of every fight in the window.
    def pooled_counts(history)
      counts = { attack: [ 0, 0, 0 ], block: [ 0, 0, 0 ] }
      history.each do |sample|
        sample.attack_heights.each { |h| counts[:attack][h - 1] += 1 if h }
        sample.block_heights.each { |h| counts[:block][h - 1] += 1 if h }
      end
      counts
    end

    # Height counts at ONE round index across the window.
    def round_counts(history, round)
      counts = { attack: [ 0, 0, 0 ], block: [ 0, 0, 0 ] }
      history.each do |sample|
        attack = sample.attack_heights[round - 1]
        block = sample.block_heights[round - 1]
        counts[:attack][attack - 1] += 1 if attack
        counts[:block][block - 1] += 1 if block
      end
      counts
    end
  end
end
