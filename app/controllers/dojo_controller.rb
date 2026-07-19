class DojoController < ApplicationController
  # The dojo landing page. Signed-out (or unverified) visitors get a marketing-ish
  # intro; verified fighters get their live inbox — challenges in and out. The
  # recent-fights and online panels are layout chrome (see ApplicationController).
  def show
    return unless living_world?

    fighter = current_fighter
    @incoming = fighter.incoming_challenges.includes(:challenger).limit(20).map(&:challenge_card_payload)
    @outgoing = fighter.outgoing_challenges.includes(:opponent).limit(20).map(&:challenge_card_payload)
  end
end
