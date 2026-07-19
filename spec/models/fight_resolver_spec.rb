require "rails_helper"

RSpec.describe FightResolver do
  # Build a round's move. Style never affects resolution, so it defaults.
  def mv(attack_height, block_height, attack_style: 0)
    { attack_height: attack_height, block_height: block_height, attack_style: attack_style }
  end

  def resolve(challenger_moves:, opponent_moves:, challenger_belt: 1, opponent_belt: 1, rng: Random.new(1))
    described_class.new(
      challenger_moves: challenger_moves,
      opponent_moves: opponent_moves,
      challenger_belt: challenger_belt,
      opponent_belt: opponent_belt,
      rng: rng
    ).resolve
  end

  describe "land vs block across all 81 height combinations (one round)" do
    heights = [ 1, 2, 3 ]

    heights.product(heights, heights, heights).each do |challenger_attack, challenger_block, opponent_attack, opponent_block|
      it "resolves c(atk #{challenger_attack}/blk #{challenger_block}) vs o(atk #{opponent_attack}/blk #{opponent_block})" do
        result = resolve(
          challenger_moves: [ mv(challenger_attack, challenger_block) ] * 3,
          opponent_moves: [ mv(opponent_attack, opponent_block) ] * 3
        )
        round = result.rounds.first

        # A hit lands unless the defender blocked at the attack's height.
        challenger_lands = opponent_block != challenger_attack
        opponent_lands = challenger_block != opponent_attack

        expect(round.challenger_damage.positive?).to eq(challenger_lands)
        expect(round.opponent_damage.positive?).to eq(opponent_lands)
      end
    end
  end

  describe "dice bounds" do
    it "keeps every landed hit within base+1..base+8 across many seeds" do
      base = Belt.base_damage_for(1)

      200.times do |seed|
        result = resolve(
          challenger_moves: [ mv(3, 2) ] * 3, # attack high, block mid
          opponent_moves: [ mv(1, 2) ] * 3,   # attack low, block mid → both always land
          rng: Random.new(seed)
        )

        result.rounds.each do |round|
          expect(round.challenger_damage).to be_between(base + 1, base + 8)
          expect(round.opponent_damage).to be_between(base + 1, base + 8)
        end
      end
    end

    it "records exactly zero for a blocked attack" do
      result = resolve(
        challenger_moves: [ mv(2, 2) ] * 3, # attack mid; opponent blocks mid → blocked
        opponent_moves: [ mv(2, 2) ] * 3
      )
      expect(result.rounds.map(&:challenger_damage)).to all(eq(0))
      expect(result.rounds.map(&:opponent_damage)).to all(eq(0))
    end
  end

  describe "knockouts" do
    it "stops processing further rounds once a fighter drops below 1 HP" do
      # Red challenger two-hits a white opponent; KO lands in round 2.
      result = resolve(
        challenger_moves: [ mv(3, 1) ] * 3, # attack high, block low → opponent (blocks low) never stops it
        opponent_moves: [ mv(3, 1) ] * 3,   # opponent lands too, but its weaker belt can't KO in time
        challenger_belt: 8,
        opponent_belt: 1
      )

      expect(result.ko).to be(true)
      expect(result.ended_early).to be(true)
      expect(result.rounds.size).to eq(2)
      expect(result.winner).to eq(:challenger)
      expect(result.opponent_hp).to be < 1
    end

    it "calls a double-KO in the same round a draw" do
      # Two red belts land on each other every round; both fall in round 3.
      result = resolve(
        challenger_moves: [ mv(3, 1) ] * 3,
        opponent_moves: [ mv(3, 1) ] * 3,
        challenger_belt: 8,
        opponent_belt: 8
      )

      expect(result.ko).to be(true)
      expect(result.winner).to be_nil
      expect(result.challenger_hp).to be < 1
      expect(result.opponent_hp).to be < 1
    end
  end

  describe "decision after three rounds" do
    it "awards the win to higher raw HP when nobody is knocked out" do
      # Challenger lands only round 1; opponent lands never. No KO.
      result = resolve(
        challenger_moves: [ mv(3, 2), mv(3, 2), mv(3, 2) ],
        opponent_moves: [ mv(2, 1), mv(2, 3), mv(2, 3) ]
      )

      expect(result.ko).to be(false)
      expect(result.ended_early).to be(false)
      expect(result.rounds.size).to eq(3)
      expect(result.winner).to eq(:challenger)
      expect(result.challenger_hp).to be > result.opponent_hp
    end

    it "draws when both fighters end on equal HP" do
      # Everything blocked both ways → both keep full, equal HP.
      result = resolve(
        challenger_moves: [ mv(2, 2) ] * 3,
        opponent_moves: [ mv(2, 2) ] * 3
      )

      expect(result.ko).to be(false)
      expect(result.winner).to be_nil
      expect(result.challenger_hp).to eq(result.opponent_hp)
    end
  end

  describe "determinism" do
    it "produces identical results for the same seed and moves" do
      moves = { challenger_moves: [ mv(3, 1), mv(1, 2), mv(2, 3) ],
                opponent_moves: [ mv(2, 3), mv(3, 1), mv(1, 2) ] }

      a = resolve(**moves, rng: Random.new(99))
      b = resolve(**moves, rng: Random.new(99))

      expect(a).to eq(b)
    end

    it "accepts FightMove-like records via duck typing" do
      record = Struct.new(:attack_height, :block_height, :attack_style)
      result = resolve(
        challenger_moves: Array.new(3) { record.new(3, 2, 0) },
        opponent_moves: Array.new(3) { record.new(1, 2, 1) }
      )
      expect(result.rounds.first.challenger_damage).to be_positive
    end
  end
end
