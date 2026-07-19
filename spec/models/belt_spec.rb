require "rails_helper"

RSpec.describe Belt do
  describe ".name_for" do
    it "names the fixed belts by index" do
      expect((0..9).map { |b| described_class.name_for(b) }).to eq(
        %w[Tofu White Yellow Orange Green Blue Purple Brown Red Black]
      )
    end

    it "names black dans open-ended beyond the array" do
      expect(described_class.name_for(10)).to eq("Black (2nd dan)")
      expect(described_class.name_for(11)).to eq("Black (3rd dan)")
      expect(described_class.name_for(13)).to eq("Black (5th dan)")
    end
  end

  describe ".threshold_for" do
    it "matches the canonical thresholds" do
      expect(described_class.threshold_for(1)).to eq(0)      # white
      expect(described_class.threshold_for(2)).to eq(300)    # yellow
      expect(described_class.threshold_for(3)).to eq(800)    # orange
      expect(described_class.threshold_for(4)).to eq(1500)   # green
      expect(described_class.threshold_for(5)).to eq(2500)   # blue
      expect(described_class.threshold_for(6)).to eq(4000)   # purple
      expect(described_class.threshold_for(7)).to eq(6000)   # brown
      expect(described_class.threshold_for(8)).to eq(8500)   # red
      expect(described_class.threshold_for(9)).to eq(12000)  # black
    end

    it "adds a fixed step per dan beyond black" do
      expect(described_class.threshold_for(10)).to eq(18000)
      expect(described_class.threshold_for(11)).to eq(24000)
    end
  end

  describe ".hp_for and .base_damage_for" do
    it "follows 56 + 6·belt and 18 + 2·belt" do
      expect(described_class.hp_for(0)).to eq(56)
      expect(described_class.hp_for(1)).to eq(62)
      expect(described_class.hp_for(9)).to eq(110)
      expect(described_class.base_damage_for(0)).to eq(18)
      expect(described_class.base_damage_for(1)).to eq(20)
      expect(described_class.base_damage_for(9)).to eq(36)
    end
  end

  describe ".for_xp" do
    it "maps negative XP to the Tofu belt" do
      expect(described_class.for_xp(-1)).to eq(0)
      expect(described_class.for_xp(-200)).to eq(0)
    end

    it "maps XP to the highest belt whose threshold it meets" do
      expect(described_class.for_xp(0)).to eq(1)
      expect(described_class.for_xp(299)).to eq(1)
      expect(described_class.for_xp(300)).to eq(2)
      expect(described_class.for_xp(12_000)).to eq(9)
    end

    it "continues open-ended into the dans" do
      expect(described_class.for_xp(18_000)).to eq(10)
      expect(described_class.for_xp(24_000)).to eq(11)
    end
  end

  describe ".demote? (hysteresis)" do
    it "demotes yellow only once XP falls 20% of the span below its threshold" do
      # yellow threshold 300, span from white (0) is 300, band = 60 → boundary 240
      expect(described_class.demote?(current_belt: 2, xp: 240)).to be(false)
      expect(described_class.demote?(current_belt: 2, xp: 239)).to be(true)
    end

    it "drops white to Tofu exactly when XP goes negative" do
      expect(described_class.demote?(current_belt: 1, xp: 0)).to be(false)
      expect(described_class.demote?(current_belt: 1, xp: -1)).to be(true)
    end

    it "never demotes from Tofu" do
      expect(described_class.demote?(current_belt: 0, xp: -200)).to be(false)
    end
  end

  describe ".settle" do
    it "promotes immediately on crossing a threshold" do
      expect(described_class.settle(current_belt: 1, xp: 300)).to eq(2)
      expect(described_class.settle(current_belt: 1, xp: 800)).to eq(3)
    end

    it "holds the belt inside the hysteresis band rather than demoting" do
      expect(described_class.settle(current_belt: 2, xp: 250)).to eq(2)
    end

    it "demotes once past the band" do
      expect(described_class.settle(current_belt: 2, xp: 239)).to eq(1)
    end

    it "drops to Tofu on negative XP and never below zero" do
      expect(described_class.settle(current_belt: 1, xp: -5)).to eq(0)
      expect(described_class.settle(current_belt: 0, xp: -200)).to eq(0)
    end
  end
end
