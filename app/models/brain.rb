# A trained, versioned {Nn::Mlp} persisted for a feature-mask tier ("novice",
# "student", "master"). +bots:train+ writes a new version each run; the bot brain
# reads the latest. Distinct from {Bots::Brain}, which is the strategy dispatcher
# that CONSUMES these weights.
class Brain < ApplicationRecord
  validates :name, presence: true
  validates :version, presence: true, numericality: { only_integer: true },
            uniqueness: { scope: :name }

  # The newest trained brain of a given name.
  #
  # @param name [String]
  # @return [Brain, nil]
  def self.latest(name)
    where(name: name).order(version: :desc).first
  end

  # Next version number to write for +name+ (so re-running training is safe).
  #
  # @param name [String]
  # @return [Integer]
  def self.next_version(name)
    (where(name: name).maximum(:version) || 0) + 1
  end

  # Per-process memoized {latest}. Bots hit this every move; the cache spares the
  # query. {clear_cache!} after training so a fresh version is picked up.
  #
  # @param name [String]
  # @return [Brain, nil]
  def self.cached_latest(name)
    @cache ||= {}
    return @cache[name] if @cache.key?(name)

    @cache[name] = latest(name)
  end

  def self.clear_cache!
    @cache = {}
  end

  # Deserialized network ready to predict.
  #
  # @return [Nn::Mlp]
  def mlp
    @mlp ||= Nn::Mlp.from_h(weights)
  end

  # Visible feature groups as symbols for {Nn::Features}.
  #
  # @return [Array<Symbol>]
  def mask
    feature_mask.map(&:to_sym)
  end
end
