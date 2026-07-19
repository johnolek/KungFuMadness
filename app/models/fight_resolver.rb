# Pure resolution of a committed fight: given both fighters' three rounds of moves
# and their snapshot belts, plays the fight out round by round and reports the
# outcome. No persistence, no XP, no I/O — {Fight#resolve!} wraps this in Phase 2.
#
# Moves are duck-typed: each entry may be a FightMove record or a plain hash and
# needs +attack_height+ and +block_height+ (1 low / 2 mid / 3 high). +attack_style+
# is carried for flavor only and never affects resolution.
#
# The RNG is injectable so the balance sim and specs stay deterministic.
class FightResolver
  ROUNDS = 3

  # A single resolved round. +challenger_damage+/+opponent_damage+ are the damage
  # each fighter *dealt* (0 = blocked); the *_hp_after values are the cumulative HP
  # each fighter has left after taking the other's hit.
  Round = Data.define(:round, :challenger_damage, :opponent_damage, :challenger_hp_after, :opponent_hp_after)

  # +winner+ is :challenger, :opponent, or nil (draw). +ko+ is true when a knockout
  # decided (or drew) the fight. +ended_early+ is true when it stopped before all
  # three rounds. +rounds+ is the ordered array of {Round}s actually played.
  Result = Data.define(:rounds, :winner, :ko, :ended_early, :challenger_hp, :opponent_hp)

  # @param challenger_moves [Array<#attack_height,#block_height>] three rounds, in order
  # @param opponent_moves [Array<#attack_height,#block_height>] three rounds, in order
  # @param challenger_belt [Integer] snapshot belt the challenger fights at
  # @param opponent_belt [Integer] snapshot belt the opponent fights at
  # @param rng [Random] injectable dice source
  def initialize(challenger_moves:, opponent_moves:, challenger_belt:, opponent_belt:, rng: Random.new)
    @challenger_moves = challenger_moves
    @opponent_moves = opponent_moves
    @challenger_belt = challenger_belt
    @opponent_belt = opponent_belt
    @rng = rng
  end

  # @return [Result]
  def resolve
    challenger_hp = Belt.hp_for(@challenger_belt)
    opponent_hp = Belt.hp_for(@opponent_belt)
    rounds = []
    ko = false
    ended_early = false

    (1..ROUNDS).each do |round|
      challenger_move = @challenger_moves[round - 1]
      opponent_move = @opponent_moves[round - 1]

      challenger_damage = damage(attacker_belt: @challenger_belt, attack: attack_height(challenger_move), block: block_height(opponent_move))
      opponent_damage = damage(attacker_belt: @opponent_belt, attack: attack_height(opponent_move), block: block_height(challenger_move))

      challenger_hp -= opponent_damage
      opponent_hp -= challenger_damage

      rounds << Round.new(
        round: round,
        challenger_damage: challenger_damage,
        opponent_damage: opponent_damage,
        challenger_hp_after: challenger_hp,
        opponent_hp_after: opponent_hp
      )

      if challenger_hp < 1 || opponent_hp < 1
        ko = true
        ended_early = round < ROUNDS
        break
      end
    end

    Result.new(
      rounds: rounds,
      winner: decide(challenger_hp, opponent_hp),
      ko: ko,
      ended_early: ended_early,
      challenger_hp: challenger_hp,
      opponent_hp: opponent_hp
    )
  end

  private

  # A hit lands unless the defender blocked at the attack's height; a landed hit
  # deals the attacker's belt base plus a fresh 1d8.
  def damage(attacker_belt:, attack:, block:)
    return 0 if block == attack

    Belt.base_damage_for(attacker_belt) + @rng.rand(1..8)
  end

  def decide(challenger_hp, opponent_hp)
    return nil if challenger_hp < 1 && opponent_hp < 1
    return :opponent if challenger_hp < 1
    return :challenger if opponent_hp < 1
    return :challenger if challenger_hp > opponent_hp
    return :opponent if opponent_hp > challenger_hp

    nil
  end

  def attack_height(move)
    read(move, :attack_height)
  end

  def block_height(move)
    read(move, :block_height)
  end

  def read(move, key)
    move.respond_to?(key) ? move.public_send(key) : move.fetch(key)
  end
end
