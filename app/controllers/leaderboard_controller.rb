class LeaderboardController < ApplicationController
  before_action :require_verified_fighter

  # How many fighters each board surfaces.
  TOP_LIMIT = 25

  # Window for the "most active" board.
  ACTIVE_WINDOW = 7.days

  # Two boards, humans and bots together: all-time XP leaders, and who has
  # settled the most fights in the last week.
  def show
    @top = Fighter.order(xp: :desc, name: :asc).limit(TOP_LIMIT)
    @active = most_active_this_week
  end

  private

  # Fighters ranked by resolved fights (as challenger or opponent) in the window.
  #
  # @return [Array<Array(Fighter, Integer)>] [fighter, fight_count], busiest first
  def most_active_this_week
    counts = Hash.new(0)
    Fight.resolved.where(resolved_at: ACTIVE_WINDOW.ago..)
         .pluck(:challenger_id, :opponent_id)
         .each do |challenger_id, opponent_id|
      counts[challenger_id] += 1
      counts[opponent_id] += 1
    end

    ranked = counts.sort_by { |_id, count| -count }.first(TOP_LIMIT)
    fighters = Fighter.where(id: ranked.map(&:first)).index_by(&:id)
    ranked.filter_map { |id, count| [ fighters[id], count ] if fighters[id] }
  end
end
