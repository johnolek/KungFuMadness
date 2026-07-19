require "rails_helper"

# The balance contract: with uniform-random play the belt curves must land 1–2
# belts of advantage inside their target win-rate envelope while keeping
# knockouts plausible and draws contained. Fixed seed + N keeps this fast and
# deterministic; the authoritative table is `bin/rails balance:simulate`.
RSpec.describe Balance do
  SEED = 12_345
  N = 2_000

  def pair(challenger_belt, opponent_belt)
    described_class.run_pair(
      challenger_belt: challenger_belt,
      opponent_belt: opponent_belt,
      fights: N,
      rng: Random.new(SEED)
    )
  end

  describe "same belt (gap 0)" do
    let(:row) { pair(1, 1) }

    it "is a near coin-flip excluding draws" do
      expect(row.higher_decisive_win_rate).to be_between(0.45, 0.55)
    end

    it "produces knockouts often enough to matter" do
      expect(row.ko_rate).to be > 0.10
    end

    it "does not drown in draws" do
      expect(row.draw_rate).to be < 0.40
    end
  end

  describe "one belt up (gap 1)" do
    it "wins 55–65% of decisive fights" do
      expect(pair(1, 2).higher_decisive_win_rate).to be_between(0.55, 0.65)
    end
  end

  describe "two belts up (gap 2)" do
    it "wins 60–70% of decisive fights at the low end" do
      expect(pair(1, 3).higher_decisive_win_rate).to be_between(0.60, 0.70)
    end

    it "stays in the envelope mid-ladder too" do
      expect(pair(4, 6).higher_decisive_win_rate).to be_between(0.60, 0.70)
    end
  end
end
