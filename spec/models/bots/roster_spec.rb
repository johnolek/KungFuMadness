require "rails_helper"

RSpec.describe Bots::Roster do
  describe ".generate" do
    subject(:specs) { described_class.generate(target: 200, seed: 1) }

    it "produces the requested number of bots" do
      expect(specs.size).to eq(200)
    end

    it "gives every bot a unique name" do
      names = specs.map { |s| s[:name] }
      expect(names.uniq.size).to eq(names.size)
    end

    it "uses only plain ASCII names — no emoji" do
      specs.each do |spec|
        expect(spec[:name]).to match(/\A[A-Za-z0-9 '()-]+\z/), "unexpected characters in #{spec[:name].inspect}"
      end
    end

    it "keeps PepsiDad the lone 9th dan" do
      dan_nines = specs.select { |s| s[:belt] == 17 }
      expect(dan_nines.map { |s| s[:name] }).to eq([ "PepsiDad" ])
    end

    it "keeps belts within the valid range" do
      expect(specs.map { |s| s[:belt] }).to all(be_between(0, 17))
    end

    it "forms a population pyramid — far more low belts than high" do
      counts = specs.group_by { |s| s[:belt] }.transform_values(&:size)
      low = (1..2).sum { |b| counts.fetch(b, 0) }
      high = (8..17).sum { |b| counts.fetch(b, 0) }
      expect(low).to be > high
    end

    it "attaches a persona and a brain type to every bot" do
      specs.each do |spec|
        expect(spec[:strategy]).to include(:persona)
        expect(spec[:strategy][:type]).to be_in(%w[pattern biased nn])
      end
    end

    it "spreads personas across multiple activity archetypes" do
      windows = specs.map { |s| s[:strategy][:persona][:activity] }.uniq
      expect(windows.size).to be > 3
    end

    it "is deterministic for a given seed" do
      expect(described_class.generate(target: 200, seed: 1)).to eq(specs)
    end
  end
end
