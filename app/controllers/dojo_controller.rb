class DojoController < ApplicationController
  # The dojo landing page. Signed-out visitors get a marketing-ish intro; verified
  # fighters get their inbox (challenges in/out) and the site-wide recent fights.
  def show
    return unless current_user&.email_verified?

    fighter = current_fighter
    @incoming = fighter.incoming_challenges.includes(:challenger).limit(20)
    @outgoing = fighter.outgoing_challenges.includes(:opponent).limit(20)
    @recent_fights = Fight.recently_resolved.includes(:challenger, :opponent, :winner).limit(15)
  end
end
