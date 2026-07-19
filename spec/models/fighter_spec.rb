require "rails_helper"

RSpec.describe Fighter, type: :model do
  subject { create(:fighter) }

  it { is_expected.to belong_to(:user).optional }
  it { is_expected.to have_many(:fight_moves).dependent(:destroy) }

  it "requires a unique name (case-insensitive)" do
    create(:fighter, name: "Iron Mantis", user: nil)
    expect(build(:fighter, name: "iron mantis", user: nil)).not_to be_valid
  end

  it "builds a valid bot with no user" do
    bot = build(:fighter, :bot)
    expect(bot).to be_valid
    expect(bot.user).to be_nil
    expect(bot.bot).to be(true)
  end

  describe "#belt_name and #tofu?" do
    it "delegates the belt name to Belt" do
      expect(build(:fighter, belt: 5).belt_name).to eq("Blue")
    end

    it "flags a sub-white fighter as tofu" do
      expect(build(:fighter, belt: 0)).to be_tofu
      expect(build(:fighter, belt: 1)).not_to be_tofu
    end
  end

  describe "scopes" do
    it "separates bots, humans, and the online set" do
      human = create(:fighter, last_seen_at: 30.seconds.ago)
      bot = create(:fighter, :bot, last_seen_at: 10.minutes.ago)

      expect(Fighter.humans).to include(human)
      expect(Fighter.bots).to include(bot)
      expect(Fighter.online).to include(human)
      expect(Fighter.online).not_to include(bot)
    end
  end
end
