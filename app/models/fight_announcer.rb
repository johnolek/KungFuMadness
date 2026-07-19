# Deterministic ring-announcer flavor for resolved fights. Pure text, no timing
# or animation: {Fight#playback_payload} calls {line} once per round so the ERB
# fallback and the Svelte playback read the same words.
#
# Selection is stable across replays — the pool index is derived from the fight
# id plus round, so a given fight always narrates itself identically. No emoji.
module FightAnnouncer
  # A landed hit whose dice roll (damage minus the belt's flat base) meets this
  # reads as a "thunderous" blow.
  THUNDEROUS_ROLL = 6

  BLOCKED_BOTH = [
    "Both fighters read each other perfectly — nothing lands!",
    "A stalemate of blocks. The dojo holds its breath.",
    "Every strike turned aside. Airtight defense on both sides!"
  ].freeze

  THUNDEROUS = [
    "A THUNDEROUS blow rocks the dojo!",
    "Bone-rattling impact — the mat trembles!",
    "A devastating strike lands flush!"
  ].freeze

  TRADED = [
    "Blows traded! Neither fighter gives an inch.",
    "They swing together — and both connect!",
    "Fists and feet fly; both find their mark!"
  ].freeze

  ONE_LANDS = [
    "A clean hit slips through the guard!",
    "One fighter finds the opening!",
    "A strike lands while the other swings at air!"
  ].freeze

  module_function

  # The narration for a single resolved round.
  #
  # @param seed [Integer] a stable per-fight seed (the fight id)
  # @param round [Integer] round number 1..3
  # @param challenger_damage [Integer] damage the challenger dealt (0 = blocked)
  # @param opponent_damage [Integer] damage the opponent dealt (0 = blocked)
  # @param challenger_base [Integer] challenger's flat base damage at their snapshot belt
  # @param opponent_base [Integer] opponent's flat base damage at their snapshot belt
  # @param ko [Boolean] whether the fight ended by knockout on this round
  # @param winner_name [String, nil] display name of the winner (nil = double-KO draw)
  # @return [String]
  def line(seed:, round:, challenger_damage:, opponent_damage:, challenger_base:, opponent_base:, ko: false, winner_name: nil)
    if ko
      return winner_name ? "IT'S OVER! #{winner_name} wins by KNOCKOUT!" \
                         : "DOUBLE KNOCKOUT! They fall together — it's a DRAW!"
    end

    pool =
      if challenger_damage.zero? && opponent_damage.zero?
        BLOCKED_BOTH
      elsif thunderous?(challenger_damage, challenger_base) || thunderous?(opponent_damage, opponent_base)
        THUNDEROUS
      elsif challenger_damage.positive? && opponent_damage.positive?
        TRADED
      else
        ONE_LANDS
      end

    pool[(seed + round) % pool.size]
  end

  # @return [Boolean] whether a landed hit's dice roll cleared {THUNDEROUS_ROLL}
  def thunderous?(damage, base)
    damage.positive? && (damage - base) >= THUNDEROUS_ROLL
  end
end
