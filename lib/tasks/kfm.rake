namespace :kfm do
  desc "One-off production bootstrap: seed the ~200-bot roster (if sparse) and " \
       "train the NN brains (only if none exist). Idempotent; safe to re-run."
  task bootstrap: :environment do
    roster_threshold = Integer(ENV.fetch("ROSTER_THRESHOLD", 150))

    if Fighter.bots.count < roster_threshold
      puts "kfm:bootstrap — seeding bot roster (have #{Fighter.bots.count}, want >= #{roster_threshold})..."
      Rails.application.load_seed
    else
      puts "kfm:bootstrap — roster already populated (#{Fighter.bots.count} bots); skipping seed."
    end

    # Brains are polish, not a hard requirement: Bots::Brain#nn_moves falls back to
    # biased sampling when the brains table is empty, so the world is playable
    # without them. Train once here so bots best-respond from real scouting.
    # Modest defaults keep this to well under a minute; override with the same env
    # vars bots:train reads (FIGHTS, BOTS, EPOCHS, HIDDEN, SEED) for a sharper net,
    # or run `bin/rails bots:train` later to add a fresh version.
    if Brain.none?
      ENV["FIGHTS"] ||= "1500"
      ENV["BOTS"]   ||= "80"
      ENV["EPOCHS"] ||= "20"
      puts "kfm:bootstrap — no trained brains; training modest brains " \
           "(FIGHTS=#{ENV['FIGHTS']} BOTS=#{ENV['BOTS']} EPOCHS=#{ENV['EPOCHS']})..."
      Rake::Task["bots:train"].invoke
    else
      puts "kfm:bootstrap — brains already trained (#{Brain.count} rows); skipping training."
    end

    puts "kfm:bootstrap — done."
  end
end
