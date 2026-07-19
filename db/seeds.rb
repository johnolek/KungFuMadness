# Starter bot roster. Phase 2 seeds a legible dozen across the low-to-mid belts;
# Phase 4 scales this to ~200 with full personas. Idempotent: re-running only
# fills in missing bots and never disturbs a bot's accumulated XP/record.
#
# Strategies:
#   pattern — fixed, fully-scoutable loops (the tutorial bots at low belts)
#   biased  — weighted height sampling + epsilon (everyone else)
#
# XP is seeded to a plausible mid-band point for the bot's belt so the roster
# doesn't all sit on a promotion boundary.

# Mid-band XP for a belt: halfway between its threshold and the next.
def mid_band_xp(belt)
  low = Belt.threshold_for(belt)
  high = Belt.threshold_for(belt + 1)
  low + (high - low) / 2
end

BOTS = [
  { name: "Drunken Willow", belt: 1,
    strategy: { type: "pattern", loop: [
      { attack_height: "low", attack_style: 0, block_height: "high" },
      { attack_height: "mid", attack_style: 0, block_height: "low" }
    ] } },
  { name: "Straw Sandal", belt: 1,
    strategy: { type: "pattern", loop: [
      { attack_height: "high", attack_style: 1, block_height: "mid" }
    ] } },
  { name: "Paper Crane", belt: 2,
    strategy: { type: "pattern", loop: [
      { attack_height: "mid", attack_style: 0, block_height: "high" },
      { attack_height: "high", attack_style: 0, block_height: "mid" },
      { attack_height: "low", attack_style: 1, block_height: "low" }
    ] } },
  { name: "Iron Mantis", belt: 3,
    strategy: { type: "biased", epsilon: 0.1,
                attack_weights: { low: 1, mid: 2, high: 3 },
                block_weights: { low: 2, mid: 2, high: 1 } } },
  { name: "Silent Cobra", belt: 3,
    strategy: { type: "biased", epsilon: 0.15,
                attack_weights: { low: 3, mid: 1, high: 1 },
                block_weights: { low: 1, mid: 2, high: 2 } } },
  { name: "Jade Tiger", belt: 4,
    strategy: { type: "biased", epsilon: 0.1,
                attack_weights: { low: 1, mid: 3, high: 2 },
                block_weights: { low: 2, mid: 1, high: 2 } } },
  { name: "Master Ping", belt: 4,
    strategy: { type: "biased", epsilon: 0.08,
                attack_weights: { low: 2, mid: 2, high: 2 },
                block_weights: { low: 1, mid: 3, high: 1 } } },
  { name: "Golden Monkey", belt: 5,
    strategy: { type: "biased", epsilon: 0.12,
                attack_weights: { low: 2, mid: 1, high: 3 },
                block_weights: { low: 3, mid: 1, high: 1 } } },
  { name: "Whispering Blade", belt: 5,
    strategy: { type: "biased", epsilon: 0.1,
                attack_weights: { low: 1, mid: 2, high: 2 },
                block_weights: { low: 1, mid: 1, high: 3 } } },
  { name: "Thunder Fist", belt: 6,
    strategy: { type: "biased", epsilon: 0.1,
                attack_weights: { low: 3, mid: 2, high: 1 },
                block_weights: { low: 2, mid: 2, high: 2 } } },
  { name: "Crimson Phoenix", belt: 6,
    strategy: { type: "biased", epsilon: 0.07,
                attack_weights: { low: 2, mid: 3, high: 2 },
                block_weights: { low: 1, mid: 2, high: 2 } } },
  { name: "Grandmaster Oyama", belt: 7,
    strategy: { type: "biased", epsilon: 0.05,
                attack_weights: { low: 2, mid: 2, high: 3 },
                block_weights: { low: 2, mid: 2, high: 2 } } },
  # Black 9th dan (belt 17). "adaptive" is a later-phase brain that currently
  # falls back to biased — the weights below are what actually drive it: a low
  # epsilon and hard-to-read, evenly-spread heights make him a menace to scout.
  { name: "PepsiDad", belt: 17,
    strategy: { type: "adaptive", epsilon: 0.05,
                attack_weights: { low: 3, mid: 4, high: 3 },
                block_weights: { low: 3, mid: 4, high: 3 } } }
].freeze

BOTS.each do |spec|
  fighter = Fighter.find_or_initialize_by(name: spec[:name])
  next if fighter.persisted?

  fighter.assign_attributes(
    bot: true,
    belt: spec[:belt],
    xp: mid_band_xp(spec[:belt]),
    strategy: spec[:strategy].deep_stringify_keys,
    last_seen_at: Time.current
  )
  fighter.save!
end

puts "Seeded bots: #{Fighter.bots.count} total (#{BOTS.size} in roster)."
