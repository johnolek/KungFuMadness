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
    @own_profile = current_fighter == @fighter

    # Scoutable match history is for sizing up OTHER fighters — your own lives on
    # the dojo homepage. Rows feed the live MatchHistory island.
    unless @own_profile
      history = @fighter.resolved_fights.includes(:challenger, :opponent, :fight_moves)
      @total_pages = [ (history.count / HISTORY_PER_PAGE.to_f).ceil, 1 ].max
      @page = params[:page].to_i.clamp(1, @total_pages)
      @history_rows = history.offset((@page - 1) * HISTORY_PER_PAGE)
                             .limit(HISTORY_PER_PAGE)
                             .map { |fight| fight.history_row_payload(viewer: @fighter, mask_for: current_fighter) }
    end

    @pending_count = @fighter.incoming_challenges.count + @fighter.outgoing_challenges.count
    @scouting = Scouting.new(fighter: @fighter)

    # Shape of the profile's challenge control: Respond when they're waiting on
    # you (carrying the fight id), disabled once you already have one out, open
    # otherwise. Mirrors the online sidebar's states.
    unless @own_profile || current_fighter.nil?
      @challenge_state =
        if (inbound = Fight.pending.find_by(challenger: @fighter, opponent: current_fighter))
          [ :respond, inbound.id ]
        elsif Fight.pending.exists?(challenger: current_fighter, opponent: @fighter)
          [ :challenged, nil ]
        else
          [ :open, nil ]
        end
    end

    # Your own profile doubles as your account page: the passkey manager (once in
    # the navbar) lives here now.
    @credentials = current_user.credentials.order(:created_at) if @own_profile
  end
end
