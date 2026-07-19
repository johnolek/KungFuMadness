class FightersController < ApplicationController
  before_action :require_verified_fighter

  # The roster / leaderboard: everyone, strongest belt first.
  def index
    @fighters = Fighter.ranked
  end

  # A public fighter profile — belt, record, and scoutable resolved-fight history.
  def show
    @fighter = Fighter.find(params[:id])
    @history = @fighter.resolved_fights.includes(:challenger, :opponent).limit(30)
    @pending_count = @fighter.incoming_challenges.count + @fighter.outgoing_challenges.count
  end
end
