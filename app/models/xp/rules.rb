module Xp
  # XP awarded and deducted for fight outcomes, and how a delta lands on a
  # fighter's stored XP. Risk cuts both ways: beating a higher belt pays out big,
  # losing to a lower belt hurts. Every tunable lives at the top so the balance
  # sim has one place to turn the dials. All figures are computed from the two
  # fighters' *snapshot* belts.
  module Rules
    WIN_BASE = 100
    # Beating a higher belt scales the win up: ×(1 + factor·gap), capped.
    WIN_ABOVE_FACTOR = 0.5
    WIN_ABOVE_CAP = 3.0
    # Beating a lower belt scales the win down: ×(1 − factor·gap), floored.
    WIN_BELOW_FACTOR = 0.35
    WIN_BELOW_FLOOR = 0.05

    LOSS_BASE = 50
    # Losing to a higher belt is softened by −per_gap·gap, but always stings a little.
    LOSS_HIGHER_PER_GAP = 20
    LOSS_HIGHER_MIN = 10
    # Losing to a lower belt is punished harder the wider the gap.
    LOSS_LOWER_PER_GAP = 40

    # A same-belt draw is a small mutual reward.
    DRAW_SAME = 10
    # A cross-belt draw pays each side a fraction of the outcome that would have
    # favored them: the underdog banks part of a would-be win, the favorite eats
    # part of a would-be loss.
    DRAW_FRACTION = 0.30

    # XP can never fall below this. The Tofu belt lives in (XP_FLOOR..0).
    XP_FLOOR = -200

    module_function

    # XP change for both fighters given an outcome, keyed :challenger/:opponent.
    #
    # @param challenger_belt [Integer] snapshot belt
    # @param opponent_belt [Integer] snapshot belt
    # @param outcome [Symbol] :challenger_win, :opponent_win, or :draw
    # @return [Hash{Symbol=>Integer}] { challenger:, opponent: }
    def deltas(challenger_belt:, opponent_belt:, outcome:)
      case outcome
      when :challenger_win
        { challenger: win_delta(my_belt: challenger_belt, their_belt: opponent_belt),
          opponent: loss_delta(my_belt: opponent_belt, their_belt: challenger_belt) }
      when :opponent_win
        { challenger: loss_delta(my_belt: challenger_belt, their_belt: opponent_belt),
          opponent: win_delta(my_belt: opponent_belt, their_belt: challenger_belt) }
      when :draw
        { challenger: draw_delta(my_belt: challenger_belt, their_belt: opponent_belt),
          opponent: draw_delta(my_belt: opponent_belt, their_belt: challenger_belt) }
      else
        raise ArgumentError, "unknown outcome #{outcome.inspect}"
      end
    end

    # XP for winning against +their_belt+ from +my_belt+.
    #
    # @param my_belt [Integer]
    # @param their_belt [Integer]
    # @return [Integer] positive XP
    def win_delta(my_belt:, their_belt:)
      gap = their_belt - my_belt

      multiplier =
        if gap.positive?
          [ 1 + WIN_ABOVE_FACTOR * gap, WIN_ABOVE_CAP ].min
        elsif gap.negative?
          [ 1 - WIN_BELOW_FACTOR * gap.abs, WIN_BELOW_FLOOR ].max
        else
          1.0
        end

      (WIN_BASE * multiplier).round
    end

    # XP for losing to +their_belt+ from +my_belt+ (negative).
    #
    # @param my_belt [Integer]
    # @param their_belt [Integer]
    # @return [Integer] negative XP
    def loss_delta(my_belt:, their_belt:)
      gap = their_belt - my_belt

      magnitude =
        if gap.positive?
          [ LOSS_BASE - LOSS_HIGHER_PER_GAP * gap, LOSS_HIGHER_MIN ].max
        elsif gap.negative?
          LOSS_BASE + LOSS_LOWER_PER_GAP * gap.abs
        else
          LOSS_BASE
        end

      -magnitude
    end

    # XP for drawing +their_belt+ from +my_belt+.
    #
    # @param my_belt [Integer]
    # @param their_belt [Integer]
    # @return [Integer]
    def draw_delta(my_belt:, their_belt:)
      return DRAW_SAME if my_belt == their_belt

      if my_belt < their_belt
        (DRAW_FRACTION * win_delta(my_belt: my_belt, their_belt: their_belt)).round
      else
        (DRAW_FRACTION * loss_delta(my_belt: my_belt, their_belt: their_belt)).round
      end
    end

    # Land a delta on a fighter's current XP, honoring the global floor and the
    # Tofu-belt rules: while sub-white (XP negative) losses are free, and any
    # positive result (a win or an underdog draw) lifts them straight to at least
    # zero — i.e. back to white. A win/draw is a non-negative delta; a loss is
    # negative. A Tofu fighter is never the favorite, so sign is unambiguous.
    #
    # @param current_xp [Integer]
    # @param delta [Integer]
    # @param current_belt [Integer] (unused today; kept for a stable call shape)
    # @return [Integer] the fighter's new XP
    def apply(current_xp:, delta:, current_belt: nil)
      new_xp =
        if current_xp.negative?
          delta.negative? ? current_xp : [ current_xp + delta, 0 ].max
        else
          current_xp + delta
        end

      [ new_xp, XP_FLOOR ].max
    end
  end
end
