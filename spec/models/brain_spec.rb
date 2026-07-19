require "rails_helper"

RSpec.describe Brain do
  def build_mlp
    Nn::Mlp.new(input_size: Nn::Features::SIZE, hidden_size: 4, seed: 1)
  end

  def store(name, version)
    described_class.create!(
      name: name, version: version,
      feature_mask: Nn::Features::MASKS.fetch(name).map(&:to_s),
      weights: build_mlp.to_h, training_meta: {}
    )
  end

  after { described_class.clear_cache! }

  describe ".latest / .next_version" do
    it "returns the highest version and the next one to write" do
      store("master", 1)
      latest = store("master", 2)

      expect(described_class.latest("master")).to eq(latest)
      expect(described_class.next_version("master")).to eq(3)
      expect(described_class.next_version("student")).to eq(1)
    end
  end

  describe ".cached_latest" do
    it "memoizes per process until the cache is cleared" do
      store("master", 1)
      first = described_class.cached_latest("master")
      store("master", 2)

      expect(described_class.cached_latest("master")).to eq(first)

      described_class.clear_cache!
      expect(described_class.cached_latest("master").version).to eq(2)
    end
  end

  describe "#mlp" do
    it "deserializes stored weights into a usable network" do
      brain = store("novice", 1)
      x = Nn::Features.build(history: [], round: 1, belt_gap: 0)

      expect(brain.mlp).to be_a(Nn::Mlp)
      expect(brain.mlp.forward(x)[:attack].sum).to be_within(1e-9).of(1.0)
    end
  end

  it "enforces a unique version per name" do
    store("master", 1)

    expect { store("master", 1) }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
