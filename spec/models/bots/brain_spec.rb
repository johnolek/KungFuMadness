require "rails_helper"

RSpec.describe Bots::Brain do
  let(:opponent) { build(:fighter) }

  describe "pattern strategy" do
    let(:bot) do
      build(:fighter, :bot, strategy: {
        "type" => "pattern",
        "loop" => [
          { "attack_height" => "low", "attack_style" => 0, "block_height" => "high" },
          { "attack_height" => "mid", "attack_style" => 1, "block_height" => "low" }
        ]
      })
    end

    it "cycles the loop deterministically across the three rounds" do
      moves = described_class.moves_for(fighter: bot, opponent: opponent, rng: Random.new(1))

      expect(moves.map { |m| m[:attack_height] }).to eq([ 1, 2, 1 ])
      expect(moves.map { |m| m[:block_height] }).to eq([ 3, 1, 3 ])
      expect(moves.map { |m| m[:round] }).to eq([ 1, 2, 3 ])
    end

    it "is independent of the RNG (fully scoutable)" do
      a = described_class.moves_for(fighter: bot, opponent: opponent, rng: Random.new(1))
      b = described_class.moves_for(fighter: bot, opponent: opponent, rng: Random.new(999))

      expect(a).to eq(b)
    end
  end

  describe "biased strategy" do
    let(:bot) do
      build(:fighter, :bot, strategy: {
        "type" => "biased",
        "epsilon" => 0.0,
        "attack_weights" => { "low" => 0, "mid" => 0, "high" => 1 },
        "block_weights" => { "low" => 1, "mid" => 0, "high" => 0 }
      })
    end

    it "always picks the only weighted height when epsilon is zero" do
      moves = described_class.moves_for(fighter: bot, opponent: opponent, rng: Random.new(7))

      expect(moves.map { |m| m[:attack_height] }).to all(eq(3))
      expect(moves.map { |m| m[:block_height] }).to all(eq(1))
    end

    it "is deterministic for a given seed" do
      weighted = build(:fighter, :bot, strategy: {
        "type" => "biased", "epsilon" => 0.3,
        "attack_weights" => { "low" => 2, "mid" => 1, "high" => 1 }
      })

      a = described_class.moves_for(fighter: weighted, opponent: opponent, rng: Random.new(42))
      b = described_class.moves_for(fighter: weighted, opponent: opponent, rng: Random.new(42))

      expect(a).to eq(b)
    end

    it "respects the weights over many samples" do
      weighted = build(:fighter, :bot, strategy: {
        "type" => "biased", "epsilon" => 0.0,
        "attack_weights" => { "low" => 8, "mid" => 1, "high" => 1 }
      })
      rng = Random.new(123)

      counts = Hash.new(0)
      300.times do
        described_class.moves_for(fighter: weighted, opponent: opponent, rng: rng)
                       .each { |m| counts[m[:attack_height]] += 1 }
      end

      expect(counts[1]).to be > counts[2]
      expect(counts[1]).to be > counts[3]
    end
  end

  describe "unknown / adaptive strategy" do
    it "falls back to biased defaults rather than raising" do
      bot = build(:fighter, :bot, strategy: { "type" => "adaptive" })

      moves = described_class.moves_for(fighter: bot, opponent: opponent, rng: Random.new(1))

      expect(moves.size).to eq(3)
      expect(moves.map { |m| m[:attack_height] }).to all(be_between(1, 3))
    end
  end

  it "always produces three well-formed rounds" do
    bot = build(:fighter, :bot, strategy: { "type" => "biased" })
    moves = described_class.moves_for(fighter: bot, opponent: opponent, rng: Random.new(5))

    moves.each do |m|
      expect(m[:attack_height]).to be_between(1, 3)
      expect(m[:block_height]).to be_between(1, 3)
      expect(m[:attack_style]).to be_between(0, 1)
    end
  end
end
