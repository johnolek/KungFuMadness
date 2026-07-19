require "rails_helper"

RSpec.describe Nn::Trainer do
  # A tiny, seeded corpus of near-deterministic heuristic bots. Kept small + few
  # epochs so the spec stays fast; the master mask still comfortably beats the
  # blind baselines because the low belts are pattern loops.
  let(:corpus) { Nn::Corpus.generate(fights: 400, roster_size: 24, seed: 1) }

  it "trains a master brain that beats the uniform baseline by a clear margin" do
    result = described_class.train(corpus: corpus, mask_name: "master", hidden_size: 12, epochs: 25, seed: 1)
    report = result[:report]
    margin = 0.05

    expect(report.attack_accuracy).to be > report.uniform_accuracy + margin
    expect(report.block_accuracy).to be > report.uniform_accuracy + margin
    expect(report.holdout_loss).to be < 2 * Math.log(3) # both heads beat a uniform predictor
  end

  it "produces a serializable network and a populated report" do
    result = described_class.train(corpus: corpus, mask_name: "student", hidden_size: 8, epochs: 10, seed: 1)

    expect(result[:mlp]).to be_a(Nn::Mlp)
    expect(result[:report].samples).to be > 0
    expect(Nn::Mlp.from_h(result[:mlp].to_h)).to be_a(Nn::Mlp)
  end
end
