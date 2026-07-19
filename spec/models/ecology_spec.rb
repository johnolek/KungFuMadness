require "rails_helper"

# The ecology contract: after the tick engine runs, the bot population must not
# collapse. This is the balance guardrail — if it ever fails, the belt/XP curves
# have drifted and the world would pile everyone at one belt or trap them in Tofu.
# Small, seeded, and in-memory (no DB/jobs/cable), so it stays fast and stable.
RSpec.describe Ecology do
  subject(:result) { described_class.run(target_fights: 800, roster_size: 120, seed: 1) }

  it "resolves the requested number of fights within the tick budget" do
    expect(result.fights).to eq(800)
    expect(result.ticks).to be < 200_000
  end

  it "runs quickly enough to live in the suite" do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    described_class.run(target_fights: 800, roster_size: 120, seed: 1)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    expect(elapsed).to be < 60
  end

  it "keeps any single belt under 40% of the population" do
    total = result.roster_size
    biggest = result.after_distribution.values.max
    expect(biggest.to_f / total).to be < 0.40
  end

  it "produces both promotions and demotions" do
    expect(result.promotions).to be > 0
    expect(result.demotions).to be > 0
  end

  it "keeps the Tofu population under 10%" do
    expect(result.tofu_population.to_f / result.roster_size).to be < 0.10
  end

  it "leaves belts 1 through 9 all inhabited" do
    (1..9).each do |belt|
      expect(result.after_distribution.fetch(belt, 0)).to be > 0, "belt #{Belt.name_for(belt)} emptied out"
    end
  end

  it "is deterministic for a given seed" do
    a = described_class.run(target_fights: 300, roster_size: 80, seed: 42)
    b = described_class.run(target_fights: 300, roster_size: 80, seed: 42)
    expect(a.after_distribution).to eq(b.after_distribution)
    expect(a.promotions).to eq(b.promotions)
  end
end
