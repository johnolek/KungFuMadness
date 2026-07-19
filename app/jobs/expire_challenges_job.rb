# Sweeps pending challenges past their deadline and flips them to expired.
# Scheduled daily (config/recurring.yml). Each flip fires the fight's own status
# broadcast, which tells the challenger their challenge lapsed (a toast) — so a
# challenge nobody answered closes cleanly instead of hanging in the inbox forever.
# The lazy expiry in Fight#actionable? still guards the resolution path between
# runs; this is the proactive sweep that clears the boards.
class ExpireChallengesJob < ApplicationJob
  queue_as :default

  # @param now [Time] injectable clock (specs pin it)
  def perform(now: Time.current)
    Fight.pending.where(expires_at: ..now).find_each do |fight|
      fight.update!(status: :expired)
    end
  end
end
