namespace :bots do
  desc "Run one bot decision tick now (logins/logouts, responses, challenges). Dev helper for the per-minute recurring job."
  task tick: :environment do
    before = Fight.resolved.count
    Bots::TickJob.perform_now
    online = Fighter.bots.online.count
    resolved = Fight.resolved.count - before
    pending = Fight.pending.where(opponent_id: Fighter.bots.select(:id)).count
    puts "bots:tick — #{online} bots online, #{resolved} fight(s) resolved this tick, #{pending} pending on bots."
  end

  desc "Train per-tier NN brains on the ecology sim corpus + real fights; store a new version each (FIGHTS=, BOTS=, EPOCHS=, HIDDEN=, SEED= to override)"
  task train: :environment do
    fights = Integer(ENV.fetch("FIGHTS", 5000))
    bots = Integer(ENV.fetch("BOTS", 120))
    epochs = Integer(ENV.fetch("EPOCHS", 40))
    hidden = Integer(ENV.fetch("HIDDEN", 16))
    seed = Integer(ENV.fetch("SEED", 1))

    puts "Kung Fu Madness — bots:train  (sim fights=#{fights}, bots=#{bots}, epochs=#{epochs}, hidden=#{hidden}, seed=#{seed})"
    puts "Each sample: a fighter's scouting features so far -> the attack/block height they actually threw next."
    puts

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    sim_corpus = Nn::Corpus.generate(fights: fights, roster_size: bots, seed: seed)
    db_corpus = Nn::Corpus.from_database
    corpus = sim_corpus + db_corpus
    puts "Corpus: #{sim_corpus.size} sim samples + #{db_corpus.size} real-fight samples = #{corpus.size} total.\n\n"

    header = format("%-9s %8s %8s %10s %12s %10s %10s %10s %10s",
                    "tier", "train", "holdout", "trainLoss", "holdoutLoss",
                    "atkAcc", "blkAcc", "uniform", "majority")
    puts header
    puts "-" * header.length

    Nn::Features::MASKS.each_key do |tier|
      result = Nn::Trainer.train(corpus: corpus, mask_name: tier, hidden_size: hidden, epochs: epochs, seed: seed)
      report = result[:report]

      puts format("%-9s %8d %8d %10.4f %12.4f %9.1f%% %9.1f%% %9.1f%% %9.1f%%",
                  tier, report.samples, report.holdout_samples,
                  report.train_loss, report.holdout_loss,
                  report.attack_accuracy * 100, report.block_accuracy * 100,
                  report.uniform_accuracy * 100, report.majority_accuracy * 100)

      Brain.create!(
        name: tier,
        version: Brain.next_version(tier),
        feature_mask: Nn::Features::MASKS.fetch(tier).map(&:to_s),
        weights: result[:mlp].to_h,
        training_meta: {
          "train_loss" => report.train_loss,
          "holdout_loss" => report.holdout_loss,
          "attack_accuracy" => report.attack_accuracy,
          "block_accuracy" => report.block_accuracy,
          "samples" => report.samples,
          "trained_at" => Time.current.iso8601,
          "source" => "sim:#{sim_corpus.size}+db:#{db_corpus.size}",
          "seed" => seed
        }
      )
    end

    Brain.clear_cache!
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    puts
    puts "Baselines: uniform = 33.3% (blind guess), majority = always-play-most-common-height."
    puts "Stored a new version of each brain (#{Brain.count} brain rows total) in #{elapsed.round(1)}s."
  end
end
