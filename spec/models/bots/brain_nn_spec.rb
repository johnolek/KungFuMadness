require "rails_helper"

RSpec.describe Bots::Brain, "nn strategy" do
  after { Brain.clear_cache! }

  let(:nn_bot) do
    build(:fighter, :bot, belt: 9, strategy: {
      "type" => "nn", "brain" => "master", "epsilon" => 0.0,
      "attack_weights" => { "low" => 0, "mid" => 1, "high" => 0 },
      "block_weights" => { "low" => 0, "mid" => 1, "high" => 0 }
    })
  end

  # Trains a net that (regardless of input) predicts the opponent always ATTACKS
  # high and always BLOCKS low, then stores it as the master brain.
  def store_always_high_attacker_brain
    mlp = Nn::Mlp.new(input_size: Nn::Features::SIZE, hidden_size: 8, seed: 1)
    rng = Random.new(1)
    samples = 300.times.map { [ Array.new(Nn::Features::SIZE) { rng.rand }, 2, 0 ] }
    mlp.train(samples: samples, epochs: 40, rng: Random.new(1))
    Brain.create!(name: "master", version: 1,
                  feature_mask: Nn::Features::MASKS["master"].map(&:to_s),
                  weights: mlp.to_h, training_meta: {})
    Brain.clear_cache!
  end

  # An opponent with a resolved fight on record (so it is scoutable).
  def scoutable_opponent
    opponent = create(:fighter, belt: 8)
    other = create(:fighter)
    fight = create(:fight, :resolved, challenger: opponent, opponent: other, winner: opponent)
    (1..3).each do |round|
      create(:fight_move, fight: fight, fighter: opponent, round: round, attack_height: 3, block_height: 1)
      create(:fight_move, fight: fight, fighter: other, round: round, attack_height: 2, block_height: 2)
    end
    opponent
  end

  describe "fallback" do
    it "uses biased sampling when the named brain is untrained" do
      opponent = create(:fighter)
      moves = described_class.moves_for(fighter: nn_bot, opponent: opponent, rng: Random.new(1))

      # Biased fallback with mid-only weights + epsilon 0 => all mids.
      expect(moves.map { |m| m[:attack_height] }).to all(eq(2))
      expect(moves.map { |m| m[:block_height] }).to all(eq(2))
    end

    it "falls back without touching the DB when the opponent has no resolved history" do
      sim_opponent = Struct.new(:belt).new(8)
      expect(Brain).not_to receive(:cached_latest)

      moves = described_class.moves_for(fighter: nn_bot, opponent: sim_opponent, rng: Random.new(1))
      expect(moves.size).to eq(3)
    end
  end

  describe "best-response with a trained brain" do
    it "blocks the height the opponent is predicted to attack" do
      store_always_high_attacker_brain
      opponent = scoutable_opponent

      moves = described_class.moves_for(fighter: nn_bot, opponent: opponent, rng: Random.new(1))

      # Net predicts opponent always attacks high => block high every round.
      expect(moves.map { |m| m[:block_height] }).to all(eq(3))
      # Net predicts opponent always blocks low => never attack low (where they block).
      expect(moves.map { |m| m[:attack_height] }).to all(satisfy { |h| h != 1 })
    end
  end

  describe "sealed-move discipline" do
    it "builds features only from resolved fights — a pending challenge's committed moves don't change them" do
      opponent = scoutable_opponent
      before = described_class.opponent_history(opponent)

      # The opponent issues a fresh challenge: their three moves are committed to
      # fight_moves right now, but the fight is pending, not resolved.
      Fight.create_challenge!(
        challenger: opponent, opponent: create(:fighter),
        moves: (1..3).map { |r| { round: r, attack_height: 1, attack_style: 0, block_height: 1 } }
      )

      after = described_class.opponent_history(opponent.reload)

      expect(after).to eq(before)
    end
  end
end
