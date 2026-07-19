module Bots
  # Resolves a single pending challenge aimed at a bot. The bot accepts and
  # commits moves via its {Brain}, unless the challenger has been farming it
  # (>= FARM_LIMIT fights in the last 24h), in which case it declines.
  #
  # No-ops cleanly if the fight vanished, already resolved, or the opponent isn't
  # actually a bot — so it's safe to enqueue speculatively and to retry.
  class RespondJob < ApplicationJob
    queue_as :default

    # Fights between the same pair within 24h that trip a bot's decline.
    FARM_LIMIT = 4
    FARM_WINDOW = 24.hours

    # @param fight_id [Integer]
    def perform(fight_id)
      fight = Fight.find_by(id: fight_id)
      return unless fight&.pending?
      return unless fight.opponent.bot?

      if farming?(fight)
        fight.decline!
      else
        moves = Brain.moves_for(fighter: fight.opponent, opponent: fight.challenger)
        fight.respond!(moves: moves)
      end
    end

    private

    def farming?(fight)
      Fight.between(fight.challenger, fight.opponent)
           .where(created_at: FARM_WINDOW.ago..)
           .where.not(id: fight.id)
           .count >= FARM_LIMIT
    end
  end
end
