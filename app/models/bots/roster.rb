module Bots
  # Generates the ~200-bot population as plain spec hashes ({ name:, belt:, strategy: }),
  # deterministically from a seed. Both db/seeds.rb (which persists them) and the
  # balance:ecology sim (which runs them in memory) build from here, so the world
  # the sim tunes against is the same world the app ships with.
  #
  # The roster is a population pyramid: crowds of white/yellow belts thinning to a
  # rare handful of blacks and dans, with a spread of "legend" personalities at the
  # low-to-mid belts (the scoutable tutorial bots) and PepsiDad alone at 9th dan.
  # Brains scale with belt — pattern loops down low (fully readable), weighted
  # sampling through the middle, trained "nn" master brains up top — and every bot
  # gets a persona whose activity window is drawn from a spread of UTC archetypes,
  # so no timezone ever finds the dojo empty.
  module Roster
    # Hand-tuned personalities kept stable by name so re-seeding never disturbs
    # their accumulated record. Personas are attached in {legend_specs}.
    LEGENDS = [
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
      { name: "PepsiDad", belt: 17,
        strategy: { type: "nn", brain: "master", epsilon: 0.05,
                    attack_weights: { low: 3, mid: 4, high: 3 },
                    block_weights: { low: 3, mid: 4, high: 3 } } }
    ].freeze

    # Relative sampling weights for the GENERATED tail, belts 0..14 — the pyramid.
    # Belt 17 is PepsiDad's alone; nobody is generated there.
    BELT_WEIGHTS = {
      0 => 3, 1 => 40, 2 => 36, 3 => 28, 4 => 22, 5 => 16, 6 => 11,
      7 => 8, 8 => 6, 9 => 4, 10 => 3, 11 => 2, 12 => 1, 13 => 1, 14 => 1
    }.freeze

    ADJECTIVES = %w[
      Drunken Iron Jade Golden Silent Crimson Thunder Whispering Shadow Laughing
      Wandering Flying Venom Mad Little Eternal Northern Southern Winged Broken
      Twin Emerald Azure Obsidian Scarlet Swift Wise Ghost Blind Immortal
      Righteous Furious Serene Ancient Nimble Stone Bamboo Copper Velvet Roaring
    ].freeze

    NOUNS = %w[
      Willow Crane Mantis Cobra Tiger Monkey Blade Fist Phoenix Dragon Fox Panther
      Scorpion Lotus Viper Falcon Wolf Sparrow Toad Serpent Eagle Leopard Bear Hawk
      Turtle Python Heron Spider Boar Palm Fang Monk Warrior Sword Staff Fan Claw
      Stance Sifu Lion
    ].freeze

    # UTC activity windows, one per archetype, chosen so every hour of the day is
    # covered by several archetypes — the dojo never goes fully dark.
    ACTIVITY_ARCHETYPES = {
      "early_bird" => [ [ 5, 9 ], [ 12, 14 ] ],
      "day_shift" => [ [ 8, 12 ], [ 13, 17 ] ],
      "afternoon" => [ [ 14, 18 ], [ 20, 22 ] ],
      "evening" => [ [ 17, 21 ], [ 21, 23 ] ],
      "night_owl" => [ [ 22, 23 ], [ 0, 3 ] ],
      "graveyard" => [ [ 0, 6 ] ],
      "split" => [ [ 6, 9 ], [ 18, 22 ] ],
      "wide" => [ [ 10, 23 ] ]
    }.freeze

    DECLINE_STYLES = %w[meek proud grudging grudging].freeze

    module_function

    # @param target [Integer] total roster size (legends included)
    # @param seed [Integer] deterministic generator seed
    # @return [Array<Hash>] specs of { name:, belt:, strategy: (with a persona) }
    def generate(target: 200, seed: 20_250_718)
      rng = Random.new(seed)
      specs = legend_specs(rng)
      taken = specs.map { |s| s[:name] }.to_set
      names = combinator_names(rng).reject { |n| taken.include?(n) }

      weighted_belts(target - specs.size, rng).each do |belt|
        name = names.shift
        specs << generated_spec(name: name, belt: belt, rng: rng)
      end

      specs
    end

    # Legends carry their hand-tuned brain but still get a generated persona so they
    # log on and off like everyone else.
    def legend_specs(rng)
      LEGENDS.map do |legend|
        strategy = deep_dup(legend[:strategy])
        strategy[:persona] = persona_for(rng)
        { name: legend[:name], belt: legend[:belt], strategy: strategy }
      end
    end

    def generated_spec(name:, belt:, rng:)
      strategy = brain_for(belt, rng)
      strategy[:persona] = persona_for(rng)
      { name: name, belt: belt, strategy: strategy }
    end

    # Mid-band XP for a belt with jitter, kept safely inside the belt's own span so
    # the seeded belt and XP never disagree.
    def seed_xp(belt, rng)
      low = Belt.threshold_for(belt)
      span = Belt.threshold_for(belt + 1) - low
      return (rng.rand * 100).round - 60 if belt.zero? # Tofu lives below zero

      low + (span * (0.2 + rng.rand * 0.6)).round
    end

    def brain_for(belt, rng)
      if belt <= 2
        rng.rand < 0.6 ? pattern_strategy(rng) : biased_strategy(rng, epsilon_range: 0.12..0.2)
      elsif belt <= 6
        biased_strategy(rng, epsilon_range: 0.08..0.16)
      else
        nn_strategy(rng)
      end
    end

    def pattern_strategy(rng)
      length = rng.rand(1..3)
      loop_moves = Array.new(length) do
        {
          attack_height: %w[low mid high].sample(random: rng),
          attack_style: rng.rand(0..1),
          block_height: %w[low mid high].sample(random: rng)
        }
      end
      { type: "pattern", loop: loop_moves }
    end

    def biased_strategy(rng, epsilon_range:)
      {
        type: "biased",
        epsilon: rand_in(epsilon_range, rng).round(2),
        attack_weights: random_weights(rng),
        block_weights: random_weights(rng)
      }
    end

    # Top belts run the trained "master" brain: predict the opponent and best-respond.
    # The flat weights + low epsilon are the biased fallback used until the brains
    # table is populated (or against opponents with no scoutable history).
    def nn_strategy(rng)
      {
        type: "nn",
        brain: "master",
        epsilon: rand_in(0.04..0.08, rng).round(2),
        attack_weights: flat_weights(rng),
        block_weights: flat_weights(rng)
      }
    end

    def persona_for(rng)
      style = ACTIVITY_ARCHETYPES.keys.sample(random: rng)
      {
        activity: ACTIVITY_ARCHETYPES.fetch(style),
        session_chance: rand_in(0.03..0.06, rng).round(3),
        session_minutes: [ 15, rng.rand(30..55) ],
        aggression: rand_in(0.012..0.035, rng).round(3),
        decline_style: DECLINE_STYLES.sample(random: rng),
        response_delay_minutes: [ 1, rng.rand(5..12) ]
      }
    end

    def random_weights(rng)
      { low: rng.rand(1..4), mid: rng.rand(1..4), high: rng.rand(1..4) }
    end

    def flat_weights(rng)
      { low: rng.rand(3..4), mid: rng.rand(3..4), high: rng.rand(3..4) }
    end

    # Every adjective+noun combination, shuffled — 800+ candidates for the ~190
    # generated names, so uniqueness is never in doubt.
    def combinator_names(rng)
      ADJECTIVES.product(NOUNS).map { |adj, noun| "#{adj} #{noun}" }.shuffle(random: rng)
    end

    # Apportions +count+ across the belts by {BELT_WEIGHTS} (largest-remainder), then
    # shuffles so the persist/insert order isn't belt-sorted.
    def weighted_belts(count, rng)
      total = BELT_WEIGHTS.values.sum.to_f
      raw = BELT_WEIGHTS.transform_values { |w| w / total * count }
      base = raw.transform_values(&:floor)
      remainder = count - base.values.sum
      raw.sort_by { |_belt, v| -(v - v.floor) }.first(remainder).each { |belt, _| base[belt] += 1 }
      base.flat_map { |belt, n| Array.new(n, belt) }.shuffle(random: rng)
    end

    def rand_in(range, rng)
      range.begin + rng.rand * (range.end - range.begin)
    end

    def deep_dup(hash)
      Marshal.load(Marshal.dump(hash))
    end
  end
end
