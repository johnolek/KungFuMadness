require "rails_helper"

RSpec.describe Nn::Features do
  def sample(attacks, blocks, won: false)
    described_class::Sample.new(attack_heights: attacks, block_heights: blocks, won: won)
  end

  describe ".build" do
    it "returns a constant-size vector regardless of history or mask" do
      full = described_class.build(history: [], round: 1, belt_gap: 0)
      masked = described_class.build(history: [], round: 1, belt_gap: 0, mask: described_class::MASKS["novice"])

      expect(full.size).to eq(described_class::SIZE)
      expect(masked.size).to eq(described_class::SIZE)
    end

    it "one-hot encodes the current round" do
      vector = described_class.build(history: [], round: 2, belt_gap: 0)

      expect(vector[described_class::GROUPS[:round_index]]).to eq([ 0.0, 1.0, 0.0 ])
    end

    it "normalizes and clamps the belt gap" do
      idx = described_class::GROUPS[:belt_gap].first

      expect(described_class.build(history: [], round: 1, belt_gap: 2)[idx]).to eq(0.5)
      expect(described_class.build(history: [], round: 1, belt_gap: 40)[idx]).to eq(1.0)
      expect(described_class.build(history: [], round: 1, belt_gap: -40)[idx]).to eq(-1.0)
    end

    it "derives overall height frequencies from the history window" do
      history = [
        sample([ 3, 3, 3 ], [ 1, 1, 1 ]),
        sample([ 3, 3, 3 ], [ 1, 1, 1 ])
      ]
      vector = described_class.build(history: history, round: 1, belt_gap: 0)

      # All attacks high, all blocks low.
      expect(vector[described_class::GROUPS[:overall_freq]]).to eq([ 0.0, 0.0, 1.0, 1.0, 0.0, 0.0 ])
    end

    it "encodes the most recent fight's move at this round index" do
      history = [ sample([ 1, 2, 3 ], [ 3, 2, 1 ]) ]
      base = described_class::GROUPS[:last_fight].first
      vector = described_class.build(history: history, round: 3, belt_gap: 0)

      # Round 3: attack high (index 2), block low (index 0).
      expect(vector[base, 6]).to eq([ 0.0, 0.0, 1.0, 1.0, 0.0, 0.0 ])
    end
  end

  describe ".apply_mask" do
    it "zeroes every group not visible to the tier" do
      full = described_class.build(
        history: [ sample([ 3, 3, 3 ], [ 1, 1, 1 ], won: true) ],
        round: 1, belt_gap: 2
      )
      novice = described_class.apply_mask(full, described_class::MASKS["novice"])

      # Novice keeps round_index + belt_gap, drops everything historical.
      expect(novice[described_class::GROUPS[:round_index]]).to eq(full[described_class::GROUPS[:round_index]])
      expect(novice[described_class::GROUPS[:belt_gap]]).to eq(full[described_class::GROUPS[:belt_gap]])
      expect(novice[described_class::GROUPS[:overall_freq]]).to all(eq(0.0))
      expect(novice[described_class::GROUPS[:last_fight]]).to all(eq(0.0))
      expect(novice[described_class::GROUPS[:form]]).to all(eq(0.0))
    end
  end

  describe ".samples_from_fights" do
    it "extracts a fighter's own moves and win flag, newest first" do
      fighter = create(:fighter)
      opponent = create(:fighter)
      fight = create(:fight, :resolved, challenger: fighter, opponent: opponent, winner: fighter)
      (1..3).each do |round|
        create(:fight_move, fight: fight, fighter: fighter, round: round,
                            attack_height: round, block_height: 4 - round)
        create(:fight_move, fight: fight, fighter: opponent, round: round,
                            attack_height: 2, block_height: 2)
      end

      samples = described_class.samples_from_fights(fighter: fighter, fights: [ fight ])

      expect(samples.first.attack_heights).to eq([ 1, 2, 3 ])
      expect(samples.first.block_heights).to eq([ 3, 2, 1 ])
      expect(samples.first.won).to be(true)
    end
  end
end
