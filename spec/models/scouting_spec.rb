require "rails_helper"

RSpec.describe Scouting do
  # Builds a resolved fight from +fighter+'s perspective with fully specified
  # committed heights and outcome, so distributions/rates are deterministic.
  def resolved_for(fighter, attacks:, blocks:, result: :loss, ko: false, opponent_belt: fighter.belt, rounds: 3, at: Time.current)
    opponent = create(:fighter, belt: opponent_belt)
    winner = case result
    when :win then fighter
    when :draw then nil
    else opponent
    end
    fight = create(
      :fight, :resolved,
      challenger: fighter, opponent: opponent,
      challenger_belt: fighter.belt, opponent_belt: opponent_belt,
      winner: winner, ko: ko, resolved_at: at
    )
    attacks.each_with_index do |attack, i|
      create(:fight_move, fight: fight, fighter: fighter, round: i + 1,
                          attack_height: attack, block_height: blocks[i])
    end
    rounds.times do |i|
      fight.fight_rounds.create!(round: i + 1, challenger_damage: 5, opponent_damage: 5,
                                 challenger_hp_after: 40, opponent_hp_after: 40)
    end
    fight
  end

  let(:fighter) { create(:fighter, belt: 3) }

  describe "distributions" do
    before do
      resolved_for(fighter, attacks: [ 3, 3, 3 ], blocks: [ 1, 1, 1 ], result: :win)
      resolved_for(fighter, attacks: [ 3, 2, 1 ], blocks: [ 1, 2, 3 ], result: :loss)
    end

    it "pools attack heights across all rounds and fights" do
      dist = described_class.new(fighter: fighter).attack_distribution

      # Six attacks total: high x4, mid x1, low x1.
      expect(dist.total).to eq(6)
      expect(dist.percent(:high)).to eq(67)
      expect(dist.percent(:mid)).to eq(17)
      expect(dist.percent(:low)).to eq(17)
    end

    it "splits distributions by round" do
      dist = described_class.new(fighter: fighter).attack_distribution(round: 3)

      # Round 3 attacks: high (win fight) and low (loss fight).
      expect(dist.count_for(:high)).to eq(1)
      expect(dist.count_for(:low)).to eq(1)
      expect(dist.count_for(:mid)).to eq(0)
    end

    it "reads block heights independently" do
      dist = described_class.new(fighter: fighter).block_distribution

      # Blocks: low x4 (1,1,1 + 1), mid x1, high x1.
      expect(dist.count_for(:low)).to eq(4)
    end
  end

  describe "#ko_rate and #average_length" do
    it "reports KO share and mean rounds fought" do
      resolved_for(fighter, attacks: [ 2, 2, 2 ], blocks: [ 2, 2, 2 ], result: :win, ko: true, rounds: 2)
      resolved_for(fighter, attacks: [ 2, 2, 2 ], blocks: [ 2, 2, 2 ], result: :loss, ko: false, rounds: 3)

      scouting = described_class.new(fighter: fighter)
      expect(scouting.ko_rate).to eq(50)
      expect(scouting.average_length).to eq(2.5)
    end
  end

  describe "#win_rate_by_gap" do
    it "buckets win rate by the opponent's snapshot belt relative to the fighter" do
      resolved_for(fighter, attacks: [ 2, 2, 2 ], blocks: [ 2, 2, 2 ], result: :win, opponent_belt: 5)
      resolved_for(fighter, attacks: [ 2, 2, 2 ], blocks: [ 2, 2, 2 ], result: :loss, opponent_belt: 5)
      resolved_for(fighter, attacks: [ 2, 2, 2 ], blocks: [ 2, 2, 2 ], result: :win, opponent_belt: 1)

      gaps = described_class.new(fighter: fighter).win_rate_by_gap
      expect(gaps[:higher].percent).to eq(50)
      expect(gaps[:lower].percent).to eq(100)
      expect(gaps[:same].total).to eq(0)
      expect(gaps[:same].percent).to be_nil
    end
  end

  describe "#recent_form and #streak" do
    it "lists newest-first results and reports the current streak" do
      resolved_for(fighter, attacks: [ 2, 2, 2 ], blocks: [ 2, 2, 2 ], result: :loss, at: 3.minutes.ago)
      resolved_for(fighter, attacks: [ 2, 2, 2 ], blocks: [ 2, 2, 2 ], result: :win, at: 2.minutes.ago)
      resolved_for(fighter, attacks: [ 2, 2, 2 ], blocks: [ 2, 2, 2 ], result: :win, ko: true, at: 1.minute.ago)

      scouting = described_class.new(fighter: fighter)
      form = scouting.recent_form
      expect(form.first).to eq(result: "W", ko: true)
      expect(form.map { |b| b[:result] }).to eq(%w[W W L])
      expect(scouting.streak).to eq(result: "W", length: 2)
    end
  end

  describe "with no history" do
    it "is empty and yields a nil strip summary" do
      scouting = described_class.new(fighter: fighter)
      expect(scouting.any?).to be(false)
      expect(scouting.sample_size).to eq(0)
      expect(scouting.ko_rate).to eq(0)
      expect(scouting.strip_summary).to be_nil
      expect(scouting.streak).to be_nil
    end
  end

  describe "#strip_summary" do
    it "packs overall attack/block percentages and KO rate" do
      resolved_for(fighter, attacks: [ 3, 3, 3 ], blocks: [ 1, 1, 1 ], result: :win)

      summary = described_class.new(fighter: fighter).strip_summary
      expect(summary[:fights]).to eq(1)
      expect(summary[:attack][:high]).to eq(100)
      expect(summary[:block][:low]).to eq(100)
    end
  end
end
