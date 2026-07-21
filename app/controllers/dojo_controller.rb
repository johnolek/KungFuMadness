class DojoController < ApplicationController
  # Resolved fights shown per page of your homepage match history.
  HISTORY_PER_PAGE = 15

  # The dojo landing page. Signed-out (or unverified) visitors get a marketing-ish
  # intro; verified fighters get their live inbox — challenges in and out — and
  # their own paginated match history (which lives here, not on the profile). The
  # recent-fights and online panels are layout chrome (see ApplicationController).
  def show
    return unless living_world?

    fighter = current_fighter
    @incoming = fighter.incoming_challenges.includes(:challenger).limit(20).map(&:challenge_card_payload)
    @outgoing = fighter.outgoing_challenges.includes(:opponent).limit(20).map(&:challenge_card_payload)

    history = fighter.resolved_fights.includes(:challenger, :opponent, :fight_moves)
    @history_total_pages = [ (history.count / HISTORY_PER_PAGE.to_f).ceil, 1 ].max
    @history_page = params[:page].to_i.clamp(1, @history_total_pages)
    @history = history.offset((@history_page - 1) * HISTORY_PER_PAGE).limit(HISTORY_PER_PAGE)
  end
end
