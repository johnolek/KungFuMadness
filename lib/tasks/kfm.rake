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

  desc "Health snapshot of the living world: Solid Queue processes, job counts, " \
       "failures, and bot-world activity. Run in the production container when " \
       "the dojo looks quiet."
  task doctor: :environment do
    heartbeat_cutoff = 5.minutes.ago
    processes = SolidQueue::Process.pluck(:kind, :last_heartbeat_at)

    puts "== Solid Queue =="
    if processes.empty?
      puts "NO PROCESSES REGISTERED — the supervisor is not running."
      puts "Check that SOLID_QUEUE_IN_PUMA=1 reaches Puma and grep the container"
      puts "logs for 'Started Supervisor' / 'Started Worker'."
    else
      processes.each do |kind, beat|
        stale = beat < heartbeat_cutoff ? "  << STALE (dead?)" : ""
        puts "#{kind}: heartbeat #{beat.iso8601}#{stale}"
      end
    end

    pending = SolidQueue::Job.where(finished_at: nil).group(:class_name).count
    finished = SolidQueue::Job.where.not(finished_at: nil).count
    failed = SolidQueue::FailedExecution.count
    puts "pending jobs: #{pending.inspect}"
    puts "finished jobs (since last hourly clear): #{finished}"
    puts "FAILED executions: #{failed}"
    if failed.positive?
      last = SolidQueue::FailedExecution.order(:created_at).last
      puts "  last failure (#{last.job.class_name}): #{last.error.inspect[0, 500]}"
    end

    puts "\n== Bot world =="
    puts "bots: #{Fighter.bots.count} (roster) / online now: #{Fighter.online.count}"
    puts "fights: #{Fight.pending.count} pending, #{Fight.resolved.count} resolved " \
         "(#{Fight.resolved.where(resolved_at: 1.hour.ago..).count} in the last hour)"
    puts "last resolved: #{Fight.recently_resolved.first&.resolved_at&.iso8601 || 'never'}"
    puts "\nNOTE: from a cold start the world ramps up slowly — bots trickle online"
    puts "(a few per minute) and only answer challenges while online, after their"
    puts "1-12 min persona delay. Expect the first bot-vs-bot fights ~10-30 minutes"
    puts "after first boot, settling into one every few minutes."
  end
end
