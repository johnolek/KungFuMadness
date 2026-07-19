# Tendency summary over a fighter's public, resolved match history — the scouting
# surface that powers profile stat-tables and the compact challenge-modal strip.
#
# Everything is derived from the fighter's committed {FightMove}s across their
# RESOLVED fights only, so a pending challenge's sealed moves can never leak in.
# Heights are the canonical 1/2/3 (low/mid/high) integers used everywhere else.
#
# Distributions come in an "overall" and a "last N" flavor (see {RECENT_WINDOW})
# and split per round (R1/R2/R3), alongside KO rate, average fight length, recent
# form, and win rate bucketed by the snapshot belt gap of each opponent.
class Scouting
  # How many of the newest fights the "recent" split and the form strip read.
  RECENT_WINDOW = 10

  # A low/mid/high height tally with percentage helpers for the bar meters.
  Distribution = Data.define(:low, :mid, :high) do
    # @return [Integer] total observations across the three heights
    def total = low + mid + high

    # @param height [Symbol, Integer] :low/:mid/:high or 1/2/3
    # @return [Integer] raw count at that height
    def count_for(height)
      case height
      when :low, 1 then low
      when :mid, 2 then mid
      when :high, 3 then high
      else 0
      end
    end

    # @param height [Symbol, Integer]
    # @return [Integer] share of the total at that height, 0..100 (0 when empty)
    def percent(height)
      return 0 if total.zero?

      (count_for(height) * 100.0 / total).round
    end

    # @return [Hash] compact percentages + sample size for JSON payloads
    def to_h = { low: percent(:low), mid: percent(:mid), high: percent(:high), n: total }
  end

  # A win tally within one belt-gap bucket.
  Rate = Data.define(:wins, :total) do
    # @return [Integer, nil] win percentage 0..100, or nil with no fights in the bucket
    def percent
      return nil if total.zero?

      (wins * 100.0 / total).round
    end
  end

  # One resolved fight reduced to the scouted fighter's own perspective.
  Entry = Data.define(:attacks, :blocks, :won, :drew, :ko, :gap, :rounds)

  # @param fighter [Fighter] the fighter being scouted
  # @param fights [Array<Fight>, nil] preloaded resolved fights (newest first);
  #   loaded from the fighter's history when omitted
  def initialize(fighter:, fights: nil)
    @fighter = fighter
    @fights = fights || fighter.resolved_fights.includes(:fight_moves, :fight_rounds).to_a
  end

  # @return [Integer] number of resolved fights analyzed
  def sample_size = entries.size

  # @return [Boolean] whether there's any resolved history to read
  def any? = entries.any?

  # @param round [Integer, nil] a single round 1..3, or nil for all rounds pooled
  # @param recent [Boolean] restrict to the last {RECENT_WINDOW} fights
  # @return [Distribution] attack-height distribution
  def attack_distribution(round: nil, recent: false)
    distribution(:attacks, round: round, recent: recent)
  end

  # @param round [Integer, nil]
  # @param recent [Boolean]
  # @return [Distribution] block-height distribution
  def block_distribution(round: nil, recent: false)
    distribution(:blocks, round: round, recent: recent)
  end

  # @return [Integer] percentage of resolved fights that ended in a knockout, 0..100
  def ko_rate
    return 0 if entries.empty?

    (entries.count(&:ko) * 100.0 / entries.size).round
  end

  # @return [Float] mean number of rounds actually fought (KOs shorten fights)
  def average_length
    return 0.0 if entries.empty?

    (entries.sum(&:rounds).to_f / entries.size).round(1)
  end

  # Win rate split by the opponent's snapshot belt relative to the fighter's.
  #
  # @return [Hash{Symbol=>Rate}] keyed :higher, :same, :lower
  def win_rate_by_gap
    buckets = { higher: [ 0, 0 ], same: [ 0, 0 ], lower: [ 0, 0 ] }
    entries.each do |entry|
      key = entry.gap.positive? ? :higher : entry.gap.negative? ? :lower : :same
      buckets[key][0] += 1 if entry.won
      buckets[key][1] += 1
    end
    buckets.transform_values { |(wins, total)| Rate.new(wins: wins, total: total) }
  end

  # Last {RECENT_WINDOW} results, newest first, for the W/L/D form strip.
  #
  # @return [Array<Hash>] each { result: "W"/"L"/"D", ko: Boolean }
  def recent_form
    entries.first(RECENT_WINDOW).map do |entry|
      { result: result_letter(entry), ko: entry.ko }
    end
  end

  # The current unbroken run of one result, from the most recent fight backward.
  #
  # @return [Hash, nil] { result: "W"/"L"/"D", length: Integer } or nil with no history
  def streak
    return nil if entries.empty?

    letter = result_letter(entries.first)
    length = entries.take_while { |entry| result_letter(entry) == letter }.size
    { result: letter, length: length }
  end

  # Compact everything the challenge-modal strip needs in one JSON-ready hash.
  #
  # @return [Hash, nil] nil when there's no resolved history to summarize
  def strip_summary
    return nil unless any?

    {
      fights: sample_size,
      ko_rate: ko_rate,
      attack: attack_distribution.to_h,
      block: block_distribution.to_h
    }
  end

  private

  attr_reader :fighter

  def entries
    @entries ||= @fights.map { |fight| entry_for(fight) }
  end

  def entry_for(fight)
    moves = fight.fight_moves.select { |m| m.fighter_id == fighter.id }.sort_by(&:round)
    Entry.new(
      attacks: moves.map(&:attack_height),
      blocks: moves.map(&:block_height),
      won: fight.winner_id == fighter.id,
      drew: fight.winner_id.nil?,
      ko: fight.ko,
      gap: opponent_belt_gap(fight),
      rounds: fight.fight_rounds.size
    )
  end

  # Opponent's snapshot belt minus the scouted fighter's snapshot belt: positive
  # means they punched up, negative means they beat up on someone below them.
  def opponent_belt_gap(fight)
    if fight.challenger_id == fighter.id
      fight.opponent_belt - fight.challenger_belt
    else
      fight.challenger_belt - fight.opponent_belt
    end
  end

  def distribution(field, round:, recent:)
    counts = [ 0, 0, 0 ]
    source(recent).each do |entry|
      heights = entry.public_send(field)
      selected = round ? [ heights[round - 1] ] : heights
      selected.each { |height| counts[height - 1] += 1 if height }
    end
    Distribution.new(low: counts[0], mid: counts[1], high: counts[2])
  end

  def source(recent)
    recent ? entries.first(RECENT_WINDOW) : entries
  end

  def result_letter(entry)
    return "W" if entry.won
    return "D" if entry.drew

    "L"
  end
end
