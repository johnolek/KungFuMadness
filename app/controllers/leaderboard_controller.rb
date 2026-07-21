class LeaderboardController < ApplicationController
  before_action :require_verified_fighter

  # How many fighters the board surfaces.
  TOP_LIMIT = 25

  # One board, humans and bots together: all-time XP leaders.
  def show
    @top = Fighter.order(xp: :desc, name: :asc).limit(TOP_LIMIT)
  end
end
