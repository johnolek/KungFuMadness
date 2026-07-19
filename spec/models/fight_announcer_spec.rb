require "rails_helper"

RSpec.describe FightAnnouncer do
  def line(**overrides)
    described_class.line(**{
      seed: 1, round: 1,
      challenger_damage: 0, opponent_damage: 0,
      challenger_base: 18, opponent_base: 18
    }.merge(overrides))
  end

  it "announces a knockout with the winner's name" do
    expect(line(ko: true, winner_name: "TestDragon [BOT]"))
      .to eq("IT'S OVER! TestDragon [BOT] wins by KNOCKOUT!")
  end

  it "announces a double knockout as a draw" do
    expect(line(ko: true, winner_name: nil)).to include("DOUBLE KNOCKOUT")
  end

  it "narrates a mutual block" do
    expect(described_class::BLOCKED_BOTH).to include(line(challenger_damage: 0, opponent_damage: 0))
  end

  it "calls a thunderous blow when a roll clears the threshold" do
    # damage 25 - base 18 = roll 7 >= THUNDEROUS_ROLL.
    expect(described_class::THUNDEROUS).to include(line(challenger_damage: 25, opponent_damage: 0))
  end

  it "narrates traded blows when both land without a big roll" do
    expect(described_class::TRADED).to include(line(challenger_damage: 20, opponent_damage: 20))
  end

  it "narrates a single clean hit" do
    expect(described_class::ONE_LANDS).to include(line(challenger_damage: 20, opponent_damage: 0))
  end

  it "is deterministic for a given seed and round" do
    first = line(seed: 42, round: 2, challenger_damage: 20, opponent_damage: 20)
    second = line(seed: 42, round: 2, challenger_damage: 20, opponent_damage: 20)
    expect(first).to eq(second)
  end
end
