require "rails_helper"

RSpec.describe Xp::Rules do
  describe ".win_delta" do
    # [my_belt, their_belt] => expected
    {
      [ 3, 3 ] => 100,   # same belt
      [ 1, 2 ] => 150,   # +1 above: 100 × 1.5
      [ 1, 3 ] => 200,   # +2 above: 100 × 2.0
      [ 1, 5 ] => 300,   # +4 above: capped at ×3
      [ 1, 9 ] => 300,   # +8 above: still capped
      [ 5, 4 ] => 65,    # −1 below: 100 × 0.65
      [ 5, 3 ] => 30,    # −2 below: 100 × 0.30
      [ 9, 1 ] => 5      # −8 below: floored at ×0.05
    }.each do |(my_belt, their_belt), expected|
      it "pays #{expected} winning at belt #{my_belt} vs #{their_belt}" do
        expect(described_class.win_delta(my_belt: my_belt, their_belt: their_belt)).to eq(expected)
      end
    end
  end

  describe ".loss_delta" do
    {
      [ 3, 3 ] => -50,    # same belt
      [ 1, 2 ] => -30,    # to +1 higher: −(50−20)
      [ 1, 3 ] => -10,    # to +2 higher: −max(10, 50−40)
      [ 1, 9 ] => -10,    # to far higher: floored magnitude 10
      [ 3, 2 ] => -90,    # to −1 lower: −(50+40)
      [ 3, 1 ] => -130    # to −2 lower: −(50+80)
    }.each do |(my_belt, their_belt), expected|
      it "docks #{expected} losing at belt #{my_belt} vs #{their_belt}" do
        expect(described_class.loss_delta(my_belt: my_belt, their_belt: their_belt)).to eq(expected)
      end
    end
  end

  describe ".draw_delta" do
    it "gives a small mutual reward on a same-belt draw" do
      expect(described_class.draw_delta(my_belt: 4, their_belt: 4)).to eq(10)
    end

    it "pays the underdog 30% of their would-be win" do
      # white draws black: would-be win 300 → 90
      expect(described_class.draw_delta(my_belt: 1, their_belt: 9)).to eq(90)
    end

    it "docks the favorite 30% of their would-be loss" do
      # black draws white: would-be loss −370 → −111
      expect(described_class.draw_delta(my_belt: 9, their_belt: 1)).to eq(-111)
    end
  end

  describe ".deltas" do
    it "pairs a challenger win with the opponent's loss" do
      # Challenger (white) beats opponent (orange, +2): challenger +200; the
      # opponent lost to a fighter two belts below, so eats the −130 penalty.
      result = described_class.deltas(challenger_belt: 1, opponent_belt: 3, outcome: :challenger_win)
      expect(result).to eq(challenger: 200, opponent: -130)
    end

    it "pairs an opponent win with the challenger's loss" do
      result = described_class.deltas(challenger_belt: 3, opponent_belt: 1, outcome: :opponent_win)
      expect(result).to eq(challenger: -130, opponent: 200)
    end

    it "gives both sides their draw delta" do
      result = described_class.deltas(challenger_belt: 1, opponent_belt: 9, outcome: :draw)
      expect(result).to eq(challenger: 90, opponent: -111)
    end

    it "rejects an unknown outcome" do
      expect { described_class.deltas(challenger_belt: 1, opponent_belt: 1, outcome: :nonsense) }
        .to raise_error(ArgumentError)
    end
  end

  describe ".apply" do
    it "adds the delta normally above zero" do
      expect(described_class.apply(current_xp: 500, delta: 100)).to eq(600)
      expect(described_class.apply(current_xp: 500, delta: -50)).to eq(450)
    end

    it "never falls below the XP floor when a big loss overshoots" do
      # White belt (positive XP) eats a −370 loss to a far-lower belt.
      expect(described_class.apply(current_xp: 10, delta: -370)).to eq(-200)
    end

    it "makes losses free while in the Tofu belt" do
      expect(described_class.apply(current_xp: -50, delta: -90)).to eq(-50)
    end

    it "lifts a Tofu fighter to at least zero on any win or draw, however small" do
      expect(described_class.apply(current_xp: -50, delta: 5)).to eq(0)
      expect(described_class.apply(current_xp: -10, delta: 200)).to eq(190)
    end
  end
end
