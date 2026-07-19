module Bots
  # Resolves a single pending challenge aimed at a bot — the DEV immediate-response
  # path, so a challenge issued from the browser settles in a few seconds without a
  # running scheduler. Production cadence is {TickJob}. The bot accepts and commits
  # moves via its {Brain}, unless its {Persona} declines (temperament / farming).
  #
  # No-ops cleanly if the fight vanished, already resolved, or the opponent isn't
  # actually a bot — so it's safe to enqueue speculatively and to retry.
  class RespondJob < ApplicationJob
    queue_as :default

    # @param fight_id [Integer]
    def perform(fight_id)
      fight = Fight.find_by(id: fight_id)
      return unless fight&.pending?
      return unless fight.opponent.bot?

      # The bot "logs on" to answer, so presence reflects the activity that a
      # response actually represents (drives the online list in dev).
      fight.opponent.touch(:last_seen_at)

      persona = Persona.for(fight.opponent)
      if persona.decline?(my_belt: fight.opponent_belt, challenger_belt: fight.challenger_belt,
                          farming: fight.farmed_by_challenger?, rng: Random.new)
        fight.decline!
      else
        moves = Brain.moves_for(fighter: fight.opponent, opponent: fight.challenger)
        fight.respond!(moves: moves)
      end
    end
  end
end
