# The bot ecology as a balance test. Runs the same decision loop as
# {Bots::TickJob} — personas log on and off, challenge online peers within belt
# reach, respond or decline per temperament — but entirely in memory against
# lightweight sim fighters, with a seeded RNG and NO database, jobs, or cable.
# Fights resolve straight through {FightResolver} and {Xp::Rules}; belts settle
# through {Belt}. So dev data is never touched and a run is fully deterministic.
#
# The point is the SHAPE the curves produce: run until N fights resolve, then read
# the belt distribution, per-tier XP percentiles, promotion/demotion churn, and the
# Tofu population. If 200 bots pile up at one belt, or nobody ever demotes, the
# math is wrong. +bin/rails balance:ecology+ prints the report; the ecology spec
# asserts the population doesn't collapse.
module Ecology
  # A tick is one simulated minute; time advances from this epoch so persona
  # activity windows rotate through a real UTC day.
  EPOCH = Time.utc(2025, 1, 6, 0, 0, 0).freeze

  # Belts either side a bot will challenge (mirrors Bots::TickJob::BELT_REACH).
  BELT_REACH = 2
  # Cooldown between fights of the same pair, in ticks (5 real minutes).
  COOLDOWN_TICKS = 5
  # Most pending challenges allowed to stack on one opponent.
  MAX_PENDING = 2

  # A mutable in-memory fighter. Carries just enough to fight, settle a belt, and
  # be scouted-by-brain (via +strategy+); +start_belt+ is remembered for the
  # per-tier percentile report.
  SimFighter = Struct.new(
    :id, :name, :belt, :xp, :strategy, :start_belt,
    :wins, :losses, :draws, :last_seen_tick, :promotions, :demotions,
    keyword_init: true
  ) do
    def online?(tick)
      last_seen_tick && tick - last_seen_tick < Ecology::ONLINE_TICKS
    end
  end

  # An outstanding challenge: snapshot belts locked at creation, challenger's moves
  # committed, waiting for the opponent to answer.
  Pending = Struct.new(:challenger, :opponent, :challenger_belt, :opponent_belt,
                       :challenger_moves, :created_tick, keyword_init: true)

  # How many ticks count as "online" (mirrors Fighter::ONLINE_WINDOW = 2 min).
  ONLINE_TICKS = 2

  Result = Struct.new(:fights, :ticks, :before_distribution, :after_distribution,
                      :tier_percentiles, :promotions, :demotions, :tofu_population,
                      :roster_size, keyword_init: true)

  module_function

  # @param target_fights [Integer] stop once this many fights resolve
  # @param roster_size [Integer] number of bots to simulate
  # @param seed [Integer] deterministic RNG seed
  # @param max_ticks [Integer] safety cap so a stalled run always terminates
  # @return [Result]
  def run(target_fights: 5000, roster_size: 200, seed: 1, max_ticks: 200_000)
    rng = Random.new(seed)
    fighters = build_fighters(roster_size, seed)
    personas = fighters.to_h { |f| [ f.id, Bots::Persona.new(f.strategy["persona"]) ] }
    before = distribution(fighters)

    pending = []
    cooldowns = {} # [a_id, b_id] (sorted) => last interaction tick
    fights = 0
    tick = 0

    while fights < target_fights && tick < max_ticks
      now = EPOCH + tick * 60
      online = advance_presence(fighters, personas, tick, now, rng)

      fights += resolve_pending(pending, online, personas, cooldowns, tick, now, rng)
      issue_challenges(online, personas, fighters, pending, cooldowns, tick, rng)

      tick += 1
    end

    Result.new(
      fights: fights,
      ticks: tick,
      before_distribution: before,
      after_distribution: distribution(fighters),
      tier_percentiles: tier_percentiles(fighters),
      promotions: fighters.sum(&:promotions),
      demotions: fighters.sum(&:demotions),
      tofu_population: fighters.count { |f| f.belt.zero? },
      roster_size: fighters.size
    )
  end

  def build_fighters(roster_size, seed)
    Bots::Roster.generate(target: roster_size, seed: seed).each_with_index.map do |spec, i|
      strategy = spec[:strategy].deep_stringify_keys
      xp = Bots::Roster.seed_xp(spec[:belt], Random.new(spec[:name].hash))
      SimFighter.new(
        id: i, name: spec[:name], belt: spec[:belt], xp: xp, strategy: strategy,
        start_belt: spec[:belt], wins: 0, losses: 0, draws: 0,
        last_seen_tick: nil, promotions: 0, demotions: 0
      )
    end
  end

  # Logs bots on and off per persona; returns the ids currently online this tick.
  def advance_presence(fighters, personas, tick, now, rng)
    online = []
    fighters.each do |f|
      persona = personas[f.id]
      if f.online?(tick)
        if !persona.active_now?(now) || persona.wants_to_logout?(rng)
          f.last_seen_tick = nil
        else
          f.last_seen_tick = tick
          online << f
        end
      elsif persona.active_now?(now) && persona.wants_to_login?(rng)
        f.last_seen_tick = tick
        online << f
      end
    end
    online
  end

  # Answers pending challenges whose online opponent is ready; resolves or declines.
  # @return [Integer] fights resolved this tick
  def resolve_pending(pending, online, personas, cooldowns, tick, now, rng)
    online_ids = online.map(&:id).to_set
    resolved = 0

    pending.reject! do |p|
      next false unless online_ids.include?(p.opponent.id)

      persona = personas[p.opponent.id]
      age = (tick - p.created_tick).to_f
      next false unless persona.ready_to_respond?(age_minutes: age, rng: rng)

      if persona.decline?(my_belt: p.opponent_belt, challenger_belt: p.challenger_belt,
                          farming: false, rng: rng)
        true # dropped, no fight
      else
        resolve_fight(p, rng)
        touch_cooldown(cooldowns, p.challenger, p.opponent, tick)
        resolved += 1
        true
      end
    end

    resolved
  end

  # Online bots, per aggression, pick a reachable opponent and open a challenge.
  def issue_challenges(online, personas, _fighters, pending, cooldowns, tick, rng)
    pending_counts = Hash.new(0)
    pending.each { |p| pending_counts[p.opponent.id] += 1 }
    outstanding = pending.map { |p| [ p.challenger.id, p.opponent.id ] }.to_set

    online.each do |bot|
      next unless personas[bot.id].wants_to_challenge?(rng)

      target = pick_target(bot, online, pending_counts, outstanding, cooldowns, tick, rng)
      next unless target

      pending << Pending.new(
        challenger: bot, opponent: target,
        challenger_belt: bot.belt, opponent_belt: target.belt,
        challenger_moves: Bots::Brain.moves_for(fighter: bot, opponent: target, rng: rng),
        created_tick: tick
      )
      pending_counts[target.id] += 1
      outstanding << [ bot.id, target.id ]
    end
  end

  def pick_target(bot, online, pending_counts, outstanding, cooldowns, tick, rng)
    online.shuffle(random: rng).find do |other|
      other.id != bot.id &&
        (other.belt - bot.belt).abs <= BELT_REACH &&
        pending_counts[other.id] < MAX_PENDING &&
        !outstanding.include?([ bot.id, other.id ]) &&
        off_cooldown?(cooldowns, bot, other, tick)
    end
  end

  # Runs the fight through the real resolver + XP rules and settles both belts,
  # counting any belt movement as promotion/demotion churn.
  def resolve_fight(p, rng)
    result = FightResolver.new(
      challenger_moves: p.challenger_moves,
      opponent_moves: Bots::Brain.moves_for(fighter: p.opponent, opponent: p.challenger, rng: rng),
      challenger_belt: p.challenger_belt,
      opponent_belt: p.opponent_belt,
      rng: rng
    ).resolve

    outcome = case result.winner
    when :challenger then :challenger_win
    when :opponent then :opponent_win
    else :draw
    end

    deltas = Xp::Rules.deltas(challenger_belt: p.challenger_belt, opponent_belt: p.opponent_belt, outcome: outcome)
    apply(p.challenger, deltas[:challenger], counter_for(result.winner, :challenger))
    apply(p.opponent, deltas[:opponent], counter_for(result.winner, :opponent))
  end

  def apply(fighter, delta, counter)
    fighter.xp = Xp::Rules.apply(current_xp: fighter.xp, delta: delta, current_belt: fighter.belt)
    settled = Belt.settle(current_belt: fighter.belt, xp: fighter.xp)
    fighter.promotions += 1 if settled > fighter.belt
    fighter.demotions += 1 if settled < fighter.belt
    fighter.belt = settled
    fighter[counter] += 1
  end

  def counter_for(winner, side)
    return :draws if winner.nil?

    winner == side ? :wins : :losses
  end

  def touch_cooldown(cooldowns, a, b, tick)
    cooldowns[pair_key(a, b)] = tick
  end

  def off_cooldown?(cooldowns, a, b, tick)
    last = cooldowns[pair_key(a, b)]
    last.nil? || tick - last >= COOLDOWN_TICKS
  end

  def pair_key(a, b)
    a.id < b.id ? [ a.id, b.id ] : [ b.id, a.id ]
  end

  def distribution(fighters)
    fighters.group_by(&:belt).transform_values(&:size).sort.to_h
  end

  # p10 / p50 / p90 of final XP, grouped by the tier each fighter STARTED in.
  def tier_percentiles(fighters)
    fighters.group_by { |f| tier_name(f.start_belt) }.transform_values do |group|
      xps = group.map(&:xp).sort
      {
        count: group.size,
        p10: percentile(xps, 0.10),
        p50: percentile(xps, 0.50),
        p90: percentile(xps, 0.90)
      }
    end
  end

  def tier_name(belt)
    case belt
    when 0..2 then "low (Tofu-Yellow)"
    when 3..5 then "mid (Orange-Blue)"
    when 6..8 then "high (Purple-Red)"
    else "elite (Black+)"
    end
  end

  def percentile(sorted, fraction)
    return 0 if sorted.empty?

    idx = (fraction * (sorted.size - 1)).round
    sorted[idx]
  end
end
