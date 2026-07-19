module Nn
  # A tiny pure-Ruby multilayer perceptron: input -> one tanh hidden layer -> two
  # independent softmax heads (attack height and block height, three classes each).
  #
  # ONE shared hidden layer feeds BOTH heads rather than training two separate
  # nets. It is the simpler-to-train option: a single forward/backward pass, one
  # serialized weight set, one training loop over one corpus — and the two tasks
  # genuinely share structure (a fighter's tendencies inform how they attack AND
  # how they block), so the shared representation helps rather than hurts.
  #
  # Plain nested arrays for the weights; the training sizes here are tiny. The RNG
  # seed makes initialization reproducible.
  class Mlp
    CLASSES = 3

    # @return [Integer]
    attr_reader :input_size, :hidden_size

    # @param input_size [Integer] length of the feature vector
    # @param hidden_size [Integer] hidden units
    # @param learning_rate [Float] SGD step size
    # @param momentum [Float] velocity retention for momentum SGD
    # @param seed [Integer] deterministic weight init
    def initialize(input_size:, hidden_size: 16, learning_rate: 0.1, momentum: 0.9, seed: 1)
      @input_size = input_size
      @hidden_size = hidden_size
      @learning_rate = learning_rate
      @momentum = momentum
      init_weights(Random.new(seed))
    end

    # Predicted class distributions for one input.
    #
    # @param input [Array<Float>]
    # @return [Hash{Symbol=>Array<Float>}] { attack: [p_low, p_mid, p_high], block: [...] }
    def forward(input)
      _h, pa, pb = forward_internal(input)
      { attack: pa, block: pb }
    end

    # Mini-batch momentum SGD.
    #
    # @param samples [Array<Array>] each [input(Array<Float>), attack_label(0..2), block_label(0..2)]
    # @param epochs [Integer]
    # @param batch_size [Integer]
    # @param rng [Random] shuffles batches deterministically
    # @return [Float] mean cross-entropy loss over the final epoch
    def train(samples:, epochs:, batch_size: 32, rng: Random.new(1))
      final_loss = 0.0
      epochs.times do
        epoch_loss = 0.0
        batches = samples.shuffle(random: rng).each_slice(batch_size).to_a
        batches.each { |batch| epoch_loss += train_batch(batch) * batch.size }
        final_loss = epoch_loss / samples.size
      end
      final_loss
    end

    # Mean loss plus argmax accuracy of each head over a labelled set.
    #
    # @param samples [Array<Array>] as in {#train}
    # @return [Hash] { loss:, attack_accuracy:, block_accuracy: }
    def evaluate(samples)
      return { loss: 0.0, attack_accuracy: 0.0, block_accuracy: 0.0 } if samples.empty?

      loss = 0.0
      attack_hits = 0
      block_hits = 0
      samples.each do |input, ya, yb|
        _h, pa, pb = forward_internal(input)
        loss += -Math.log(clamp(pa[ya])) - Math.log(clamp(pb[yb]))
        attack_hits += 1 if argmax(pa) == ya
        block_hits += 1 if argmax(pb) == yb
      end
      n = samples.size.to_f
      { loss: loss / n, attack_accuracy: attack_hits / n, block_accuracy: block_hits / n }
    end

    # @return [Hash] weights + config, JSON/jsonb-safe (string keys, nested arrays)
    def to_h
      {
        "input_size" => @input_size,
        "hidden_size" => @hidden_size,
        "learning_rate" => @learning_rate,
        "momentum" => @momentum,
        "w1" => @w1, "b1" => @b1,
        "w2a" => @w2a, "b2a" => @b2a,
        "w2b" => @w2b, "b2b" => @b2b
      }
    end

    # Rebuilds a net from {#to_h} output (tolerates string keys and jsonb integers).
    #
    # @param hash [Hash]
    # @return [Mlp]
    def self.from_h(hash)
      h = hash.transform_keys(&:to_s)
      mlp = new(
        input_size: h["input_size"].to_i,
        hidden_size: h["hidden_size"].to_i,
        learning_rate: (h["learning_rate"] || 0.1).to_f,
        momentum: (h["momentum"] || 0.9).to_f
      )
      mlp.load_weights!(
        w1: h["w1"], b1: h["b1"],
        w2a: h["w2a"], b2a: h["b2a"],
        w2b: h["w2b"], b2b: h["b2b"]
      )
      mlp
    end

    # Overwrites the weights from deserialized arrays, coercing every value to Float.
    def load_weights!(w1:, b1:, w2a:, b2a:, w2b:, b2b:)
      @w1 = float_matrix(w1)
      @b1 = float_vector(b1)
      @w2a = float_matrix(w2a)
      @b2a = float_vector(b2a)
      @w2b = float_matrix(w2b)
      @b2b = float_vector(b2b)
      reset_velocities
      self
    end

    private

    def init_weights(rng)
      in_scale = 1.0 / Math.sqrt(@input_size)
      hid_scale = 1.0 / Math.sqrt(@hidden_size)
      @w1 = random_matrix(@hidden_size, @input_size, in_scale, rng)
      @b1 = Array.new(@hidden_size, 0.0)
      @w2a = random_matrix(CLASSES, @hidden_size, hid_scale, rng)
      @b2a = Array.new(CLASSES, 0.0)
      @w2b = random_matrix(CLASSES, @hidden_size, hid_scale, rng)
      @b2b = Array.new(CLASSES, 0.0)
      reset_velocities
    end

    def reset_velocities
      @vw1 = zeros_like(@w1)
      @vb1 = Array.new(@b1.size, 0.0)
      @vw2a = zeros_like(@w2a)
      @vb2a = Array.new(@b2a.size, 0.0)
      @vw2b = zeros_like(@w2b)
      @vb2b = Array.new(@b2b.size, 0.0)
    end

    # @return [Array(Array<Float>, Array<Float>, Array<Float>)] hidden, attack probs, block probs
    def forward_internal(input)
      h = Array.new(@hidden_size)
      @hidden_size.times do |j|
        row = @w1[j]
        sum = @b1[j]
        input.each_index { |i| sum += row[i] * input[i] }
        h[j] = Math.tanh(sum)
      end
      [ h, softmax(head_logits(@w2a, @b2a, h)), softmax(head_logits(@w2b, @b2b, h)) ]
    end

    def head_logits(weights, bias, h)
      Array.new(CLASSES) do |k|
        row = weights[k]
        sum = bias[k]
        @hidden_size.times { |j| sum += row[j] * h[j] }
        sum
      end
    end

    # One gradient step over a batch. @return [Float] mean loss on the batch.
    def train_batch(batch)
      gw1 = zeros_like(@w1)
      gb1 = Array.new(@hidden_size, 0.0)
      gw2a = zeros_like(@w2a)
      gb2a = Array.new(CLASSES, 0.0)
      gw2b = zeros_like(@w2b)
      gb2b = Array.new(CLASSES, 0.0)
      total_loss = 0.0

      batch.each do |input, ya, yb|
        h, pa, pb = forward_internal(input)
        total_loss += -Math.log(clamp(pa[ya])) - Math.log(clamp(pb[yb]))

        dza = Array.new(CLASSES) { |k| pa[k] - (k == ya ? 1.0 : 0.0) }
        dzb = Array.new(CLASSES) { |k| pb[k] - (k == yb ? 1.0 : 0.0) }
        dh = Array.new(@hidden_size, 0.0)

        CLASSES.times do |k|
          dzak = dza[k]
          dzbk = dzb[k]
          ga = gw2a[k]
          gb = gw2b[k]
          wa = @w2a[k]
          wb = @w2b[k]
          @hidden_size.times do |j|
            hj = h[j]
            ga[j] += dzak * hj
            gb[j] += dzbk * hj
            dh[j] += wa[j] * dzak + wb[j] * dzbk
          end
          gb2a[k] += dzak
          gb2b[k] += dzbk
        end

        @hidden_size.times do |j|
          dz1 = dh[j] * (1.0 - h[j] * h[j])
          g1 = gw1[j]
          input.each_index { |i| g1[i] += dz1 * input[i] }
          gb1[j] += dz1
        end
      end

      scale = 1.0 / batch.size
      step_matrix(@w1, @vw1, gw1, scale)
      step_vector(@b1, @vb1, gb1, scale)
      step_matrix(@w2a, @vw2a, gw2a, scale)
      step_vector(@b2a, @vb2a, gb2a, scale)
      step_matrix(@w2b, @vw2b, gw2b, scale)
      step_vector(@b2b, @vb2b, gb2b, scale)

      total_loss * scale
    end

    def step_matrix(weights, velocity, grad, scale)
      weights.each_index do |r|
        w = weights[r]
        v = velocity[r]
        g = grad[r]
        w.each_index do |c|
          v[c] = @momentum * v[c] - @learning_rate * g[c] * scale
          w[c] += v[c]
        end
      end
    end

    def step_vector(bias, velocity, grad, scale)
      bias.each_index do |i|
        velocity[i] = @momentum * velocity[i] - @learning_rate * grad[i] * scale
        bias[i] += velocity[i]
      end
    end

    def softmax(logits)
      max = logits.max
      exps = logits.map { |z| Math.exp(z - max) }
      sum = exps.sum
      exps.map { |e| e / sum }
    end

    def argmax(vector)
      best = 0
      vector.each_index { |i| best = i if vector[i] > vector[best] }
      best
    end

    def clamp(probability)
      probability.clamp(1e-12, 1.0)
    end

    def random_matrix(rows, cols, scale, rng)
      Array.new(rows) { Array.new(cols) { (rng.rand * 2.0 - 1.0) * scale } }
    end

    def zeros_like(matrix)
      matrix.map { |row| Array.new(row.size, 0.0) }
    end

    def float_matrix(matrix)
      matrix.map { |row| row.map(&:to_f) }
    end

    def float_vector(vector)
      vector.map(&:to_f)
    end
  end
end
