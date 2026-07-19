namespace :balance do
  desc "Random-play win-rate envelope by belt gap (N=, SEED= to override)"
  task simulate: :environment do
    fights = Integer(ENV.fetch("N", 5000))
    seed = Integer(ENV.fetch("SEED", 1))

    puts "Kung Fu Madness — balance:simulate  (N=#{fights}/pair, seed=#{seed})"
    puts "HP(belt) = #{Belt::HP_BASE} + #{Belt::HP_PER_BELT}·belt   " \
         "base_damage(belt) = #{Belt::DAMAGE_BASE} + #{Belt::DAMAGE_PER_BELT}·belt + 1d8"
    puts

    header = format("%-14s %5s  %8s %8s %6s %6s %7s   %s",
                    "pair", "gap", "higher%", "lower%", "draw%", "ko%", "avgRnd", "decisive higher%")
    puts header
    puts "-" * header.length

    Balance.sweep(fights: fights, seed: seed).each do |row|
      puts format("%-14s %5d  %7.1f%% %7.1f%% %5.1f%% %5.1f%% %7.2f   %13.1f%%",
                  "#{Belt.name_for(row.challenger_belt)} v #{Belt.name_for(row.opponent_belt)}",
                  row.gap,
                  row.higher_win_rate * 100,
                  row.lower_win_rate * 100,
                  row.draw_rate * 100,
                  row.ko_rate * 100,
                  row.avg_rounds,
                  row.higher_decisive_win_rate * 100)
    end
  end

  desc "Bot-ecology sim: run the tick engine in memory until N fights resolve; report the population (N=, BOTS=, SEED= to override)"
  task ecology: :environment do
    target = Integer(ENV.fetch("N", 5000))
    roster = Integer(ENV.fetch("BOTS", 200))
    seed = Integer(ENV.fetch("SEED", 1))

    puts "Kung Fu Madness — balance:ecology  (target=#{target} fights, roster=#{roster}, seed=#{seed})"
    puts "In-memory sim: personas drive logins/challenges/responses; fights resolve via FightResolver + Xp::Rules. No DB/jobs/cable."
    puts

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = Ecology.run(target_fights: target, roster_size: roster, seed: seed)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    puts "Resolved #{result.fights} fights over #{result.ticks} ticks in #{elapsed.round(1)}s.\n\n"

    puts "Belt distribution (before -> after):"
    puts format("  %-18s %8s %8s", "belt", "before", "after")
    puts "  " + "-" * 36
    belts = (result.before_distribution.keys | result.after_distribution.keys).sort
    belts.each do |belt|
      puts format("  %-18s %8d %8d", Belt.name_for(belt),
                  result.before_distribution.fetch(belt, 0),
                  result.after_distribution.fetch(belt, 0))
    end
    puts

    puts "Final XP percentiles by starting tier:"
    puts format("  %-22s %6s %8s %8s %8s", "starting tier", "n", "p10", "p50", "p90")
    puts "  " + "-" * 54
    result.tier_percentiles.sort_by { |tier, _| tier }.each do |tier, pct|
      puts format("  %-22s %6d %8d %8d %8d", tier, pct[:count], pct[:p10], pct[:p50], pct[:p90])
    end
    puts

    puts "Churn: #{result.promotions} promotions, #{result.demotions} demotions."
    puts "Tofu population (final): #{result.tofu_population} / #{result.roster_size}."
  end
end
