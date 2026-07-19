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
end
