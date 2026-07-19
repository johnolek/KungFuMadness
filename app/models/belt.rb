# Belt progression: names, XP thresholds, and the combat stats each belt confers.
# Belts are stored as an integer index on Fighter. Index 0 is the joke sub-white
# "Tofu" belt (XP below zero); 1 is white through 9 black, and 10+ are open-ended
# black dans. All game math that depends on belt lives here so the balance sim
# has a single place to tune.
module Belt
  # Index-aligned belt names. Index 0 = Tofu (joke sub-white), 9 = Black. Beyond
  # the array (dans) is handled by {name_for}.
  NAMES = %w[Tofu White Yellow Orange Green Blue Purple Brown Red Black].freeze

  # XP required to hold each belt, indexed by belt. Tofu (0) and White (1) both
  # anchor at 0; XP below zero is what drops a fighter into Tofu. Belts past the
  # array (black dans) add {DAN_STEP} each — see {threshold_for}.
  THRESHOLDS = [ 0, 0, 300, 800, 1500, 2500, 4000, 6000, 8500, 12000 ].freeze

  # XP between consecutive black-dan belts (belt 9 and up).
  DAN_STEP = 6000

  # Highest fixed belt index (black). Above this is open-ended dans.
  BLACK = 9

  # Fraction of a belt's span a fighter must fall below the threshold before
  # demoting — the hysteresis band that stops belt flip-flopping on the boundary.
  DEMOTION_HYSTERESIS = 0.20

  # Base combat constants. Tuned by the balance simulation (bin/rails
  # balance:simulate): a raised HP/damage base flattens the outsized relative
  # advantage a belt gap gives at the low end, keeping every gap inside its
  # target win-rate envelope while leaving knockouts plentiful.
  HP_BASE = 56
  HP_PER_BELT = 6
  DAMAGE_BASE = 18
  DAMAGE_PER_BELT = 2

  module_function

  # @param belt [Integer]
  # @return [Integer] hit points a fighter fights with at this belt
  def hp_for(belt)
    HP_BASE + HP_PER_BELT * belt
  end

  # @param belt [Integer]
  # @return [Integer] the flat damage every landed hit deals before the dice roll
  def base_damage_for(belt)
    DAMAGE_BASE + DAMAGE_PER_BELT * belt
  end

  # @param belt [Integer]
  # @return [Integer] cumulative XP required to reach this belt (open-ended for dans)
  def threshold_for(belt)
    return 0 if belt <= 1
    return THRESHOLDS[belt] if belt <= BLACK

    THRESHOLDS[BLACK] + (belt - BLACK) * DAN_STEP
  end

  # The belt an amount of XP alone would place a fighter at, ignoring hysteresis.
  # Negative XP is the Tofu belt; otherwise the highest belt whose threshold the
  # XP meets. Open-ended into the dans.
  #
  # @param xp [Integer]
  # @return [Integer] belt index
  def for_xp(xp)
    return 0 if xp.negative?

    belt = 1
    belt += 1 while xp >= threshold_for(belt + 1)
    belt
  end

  # Whether a fighter currently at +current_belt+ should drop a belt given +xp+.
  # Demotion lags promotion: XP must fall a fifth of the belt's span below its
  # threshold first (for white this is simply "XP went negative" → Tofu).
  #
  # @param current_belt [Integer]
  # @param xp [Integer]
  # @return [Boolean]
  def demote?(current_belt:, xp:)
    return false if current_belt <= 0

    span = threshold_for(current_belt) - threshold_for(current_belt - 1)
    xp < threshold_for(current_belt) - DEMOTION_HYSTERESIS * span
  end

  # The belt a fighter should hold after a fight, applying immediate promotion and
  # hysteresis-guarded demotion around their stored +current_belt+. Steps one belt
  # at a time so a large swing settles correctly.
  #
  # @param current_belt [Integer]
  # @param xp [Integer]
  # @return [Integer] the settled belt index
  def settle(current_belt:, xp:)
    belt = current_belt
    belt += 1 while xp >= threshold_for(belt + 1)
    belt -= 1 while demote?(current_belt: belt, xp: xp)
    [ belt, 0 ].max
  end

  # @param belt [Integer]
  # @return [String] display name, including "Black (Nth dan)" past the array
  def name_for(belt)
    return NAMES[belt] if belt <= BLACK

    "Black (#{(belt - BLACK + 1).ordinalize} dan)"
  end
end
