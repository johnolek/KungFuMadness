class FightersController < ApplicationController
  before_action :require_verified_fighter

  # The roster / leaderboard: everyone, strongest belt first.
  def index
    @fighters = Fighter.ranked
  end

  # Resolved fights shown per page of a profile's match history.
  HISTORY_PER_PAGE = 25

  # A public fighter profile — belt, record, and scoutable resolved-fight history,
  # paginated newest-first with simple offset paging.
  def show
    @fighter = Fighter.find(params[:id])
    history = @fighter.resolved_fights.includes(:challenger, :opponent)

    @total_pages = [ (history.count / HISTORY_PER_PAGE.to_f).ceil, 1 ].max
    @page = params[:page].to_i.clamp(1, @total_pages)
    @history = history.offset((@page - 1) * HISTORY_PER_PAGE).limit(HISTORY_PER_PAGE)

    @pending_count = @fighter.incoming_challenges.count + @fighter.outgoing_challenges.count
  end
end
