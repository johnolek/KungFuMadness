module Nn
  # Trains one tier's brain from a {Corpus} of unmasked samples: applies the tier's
  # feature mask, splits off a holdout, fits an {Mlp}, and reports loss/accuracy
  # against two naive baselines — uniform guessing (1/3) and majority-class
  # (always predict the most common height in the training labels).
  module Trainer
    DEFAULT_HIDDEN = 16
    DEFAULT_EPOCHS = 40
    DEFAULT_HOLDOUT = 0.2

    # Metrics for one trained tier, ready to print and to store as training_meta.
    Report = Data.define(
      :mask_name, :samples, :holdout_samples,
      :train_loss, :holdout_loss,
      :attack_accuracy, :block_accuracy,
      :uniform_accuracy, :majority_accuracy
    )

    module_function

    # @param corpus [Array<Corpus::Sample>] unmasked labelled samples
    # @param mask_name [String] one of {Features::MASKS} keys
    # @param hidden_size [Integer]
    # @param epochs [Integer]
    # @param holdout_fraction [Float]
    # @param seed [Integer] deterministic split + init + batch shuffle
    # @return [Hash] { mlp: Mlp, report: Report }
    def train(corpus:, mask_name:, hidden_size: DEFAULT_HIDDEN, epochs: DEFAULT_EPOCHS,
              holdout_fraction: DEFAULT_HOLDOUT, seed: 1)
      mask = Features::MASKS.fetch(mask_name)
      masked = corpus.map { |s| [ Features.apply_mask(s.input, mask), s.attack, s.block ] }
      train_set, holdout = split(masked, holdout_fraction, Random.new(seed))

      mlp = Mlp.new(input_size: Features::SIZE, hidden_size: hidden_size, seed: seed)
      train_loss = mlp.train(samples: train_set, epochs: epochs, rng: Random.new(seed))
      eval = mlp.evaluate(holdout)

      report = Report.new(
        mask_name: mask_name,
        samples: train_set.size,
        holdout_samples: holdout.size,
        train_loss: train_loss.round(4),
        holdout_loss: eval[:loss].round(4),
        attack_accuracy: eval[:attack_accuracy].round(4),
        block_accuracy: eval[:block_accuracy].round(4),
        uniform_accuracy: (1.0 / Features::HEIGHTS.size).round(4),
        majority_accuracy: majority_accuracy(train_set, holdout).round(4)
      )

      { mlp: mlp, report: report }
    end

    def split(samples, holdout_fraction, rng)
      shuffled = samples.shuffle(random: rng)
      cut = (shuffled.size * (1.0 - holdout_fraction)).round
      [ shuffled.first(cut), shuffled.drop(cut) ]
    end

    # Accuracy of always predicting the training set's most common attack and block
    # height, evaluated on the holdout — the "frequency-following" baseline.
    def majority_accuracy(train_set, holdout)
      return 0.0 if holdout.empty?

      top_attack = mode(train_set.map { |s| s[1] })
      top_block = mode(train_set.map { |s| s[2] })
      hits = holdout.sum { |s| (s[1] == top_attack ? 1 : 0) + (s[2] == top_block ? 1 : 0) }
      hits.to_f / (holdout.size * 2)
    end

    def mode(labels)
      labels.tally.max_by { |_label, count| count }&.first || 0
    end
  end
end
