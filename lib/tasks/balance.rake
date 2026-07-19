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
end
