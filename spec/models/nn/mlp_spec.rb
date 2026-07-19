require "rails_helper"

RSpec.describe Nn::Mlp do
  let(:input_size) { 6 }

  def random_input(rng)
    Array.new(input_size) { rng.rand * 2 - 1 }
  end

  describe "#forward" do
    it "returns two 3-class distributions that each sum to 1" do
      mlp = described_class.new(input_size: input_size, hidden_size: 8, seed: 1)
      out = mlp.forward(random_input(Random.new(1)))

      expect(out[:attack].size).to eq(3)
      expect(out[:block].size).to eq(3)
      expect(out[:attack].sum).to be_within(1e-9).of(1.0)
      expect(out[:block].sum).to be_within(1e-9).of(1.0)
    end
  end

  describe "seeded init" do
    it "is deterministic for a given seed and differs across seeds" do
      x = random_input(Random.new(42))
      same = described_class.new(input_size: input_size, seed: 7).forward(x)
      again = described_class.new(input_size: input_size, seed: 7).forward(x)
      other = described_class.new(input_size: input_size, seed: 8).forward(x)

      expect(same).to eq(again)
      expect(same).not_to eq(other)
    end
  end

  describe "#train" do
    it "learns a separable mapping (loss drops, argmax matches the target)" do
      rng = Random.new(3)
      # Attack label = sign of feature 0; block label = sign of feature 1.
      samples = 400.times.map do
        x = random_input(rng)
        [ x, x[0] > 0 ? 2 : 0, x[1] > 0 ? 2 : 0 ]
      end
      mlp = described_class.new(input_size: input_size, hidden_size: 12, seed: 1)

      before = mlp.evaluate(samples)
      mlp.train(samples: samples, epochs: 60, rng: Random.new(1))
      after = mlp.evaluate(samples)

      expect(after[:loss]).to be < before[:loss]
      expect(after[:attack_accuracy]).to be > 0.9
      expect(after[:block_accuracy]).to be > 0.9
    end
  end

  describe "serialization" do
    it "round-trips through to_h/from_h with identical predictions" do
      mlp = described_class.new(input_size: input_size, hidden_size: 8, seed: 5)
      mlp.train(samples: 50.times.map { [ random_input(Random.new(1)), 1, 2 ] }, epochs: 5)

      restored = described_class.from_h(JSON.parse(mlp.to_h.to_json))
      x = random_input(Random.new(9))

      expect(restored.forward(x)).to eq(mlp.forward(x))
    end
  end
end
