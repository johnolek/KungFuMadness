require "rails_helper"

RSpec.describe FightMove, type: :model do
  subject { build(:fight_move) }

  it { is_expected.to belong_to(:fight) }
  it { is_expected.to belong_to(:fighter) }

  it { is_expected.to validate_inclusion_of(:round).in_range(1..3) }
  it { is_expected.to validate_inclusion_of(:attack_height).in_array([ 1, 2, 3 ]) }
  it { is_expected.to validate_inclusion_of(:block_height).in_array([ 1, 2, 3 ]) }
  it { is_expected.to validate_inclusion_of(:attack_style).in_array([ 0, 1 ]) }

  it "forbids two moves for the same fighter in the same round of a fight" do
    fight = create(:fight)
    fighter = fight.challenger
    create(:fight_move, fight: fight, fighter: fighter, round: 1)
    dup = build(:fight_move, fight: fight, fighter: fighter, round: 1)
    expect(dup).not_to be_valid
  end
end
