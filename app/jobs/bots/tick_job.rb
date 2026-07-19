module Bots
  # Sweeps every bot's pending incoming challenges and enqueues a {RespondJob}
  # for each, spread over a short delay so the world resolves in a lifelike
  # trickle rather than all at once. Phase 2 keeps the tick minimal — respond and
  # decline only; the full persona-driven tick (logins, organic challenging)
  # arrives in Phase 4. Manually invocable in dev: `Bots::TickJob.perform_now`.
  class TickJob < ApplicationJob
    queue_as :default

    def perform
      Fight.pending
           .where(opponent_id: Fighter.bots.select(:id))
           .find_each do |fight|
        RespondJob.set(wait: rand(1..15).seconds).perform_later(fight.id)
      end
    end
  end
end
