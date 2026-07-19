# Rust: high belts that stop fighting slowly slide. Scheduled daily
# (config/recurring.yml). A fighter above the blue floor who hasn't resolved a
# fight in {IDLE_PERIOD} bleeds {RUST_RATE} of its XP per run, its belt resettling
# afterward. XP is clamped at the blue threshold, so rust can walk a brown down
# through purple but never past blue — an idle champion cools off, it doesn't get
# dumped into the beginner belts. Any belt drop announces itself through the
# fighter's own belt-change broadcast, so the dojo ticker shows the fade.
#
# Eligibility is "above the blue floor and idle" (belt > blue). The plan frames
# rust as a brown+ concern; gating one notch lower is what lets the documented
# brown -> purple -> blue slide actually complete across successive daily runs and
# come to rest exactly on the blue floor, instead of stalling at purple.
class RustDecayJob < ApplicationJob
  queue_as :default

  RUST_RATE = 0.01
  IDLE_PERIOD = 14.days
  # Rust never demotes below this belt (Blue); its threshold is the XP floor.
  FLOOR_BELT = 5

  # @param now [Time] injectable clock (specs/sim pin it)
  def perform(now: Time.current)
    floor_xp = Belt.threshold_for(FLOOR_BELT)

    Fighter.where(belt: (FLOOR_BELT + 1)..)
           .where(last_fought_at: ..(now - IDLE_PERIOD))
           .where(xp: (floor_xp + 1)..)
           .find_each do |fighter|
      decayed = [ (fighter.xp * (1 - RUST_RATE)).floor, floor_xp ].max
      next if decayed == fighter.xp

      fighter.xp = decayed
      fighter.belt = Belt.settle(current_belt: fighter.belt, xp: decayed)
      fighter.save!
    end
  end
end
