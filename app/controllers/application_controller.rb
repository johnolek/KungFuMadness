class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :current_user, :current_fighter, :signed_in?, :living_world?

  # The recent-fights and online sidebars are part of the chrome on every game
  # page, so their seed data is prepared here rather than per-controller.
  before_action :prepare_living_world_sidebars

  private

  # Whether the current request should render the living-world layout (the two
  # sidebars, the challenge modal, the cable subscriptions). True only for a
  # signed-in, email-verified fighter.
  def living_world?
    current_user&.email_verified? && current_fighter.present?
  end

  # How many fighters the online sidebar seeds with, and how many recent fights.
  SIDEBAR_ONLINE_LIMIT = 40
  SIDEBAR_RECENT_LIMIT = 20

  def prepare_living_world_sidebars
    return unless living_world?

    @sidebar_recent_fights = Fight.recently_resolved
                                  .includes(:challenger, :opponent, :winner, :fight_moves)
                                  .limit(SIDEBAR_RECENT_LIMIT)
                                  .map { |fight| fight.ticker_payload(mask_for: current_fighter) }
    @sidebar_online = build_online_sidebar(current_fighter)
    # Seeded as id lists (not counts) so the nav badges can dedupe live cable
    # events against what the server already counted.
    @nav_incoming_ids = current_fighter.incoming_challenges.ids
    @nav_outgoing_ids = current_fighter.outgoing_challenges.ids
  end

  # One row per online-or-recently-offline fighter — including yourself, slotted
  # into rank order so you can see at a glance how you stack up and who fights
  # near your level. Recently offline fighters (inside RECENT_OFFLINE_GRACE) ride
  # along dimmed but still challengeable, with the seconds until they age out so
  # the client can drop them on time. Each other fighter is tagged with your
  # standing challenge state toward them: "respond" when they have a pending
  # challenge waiting on you (carrying its id), "challenged" when you already
  # have a pending one out to them, or "open" when the mat is clear. Your own
  # row is tagged "you".
  #
  # @param viewer [Fighter]
  # @return [Array<Hash>]
  def build_online_sidebar(viewer)
    seen_window = Fighter::ONLINE_WINDOW + Fighter::RECENT_OFFLINE_GRACE
    roster = Fighter.online(within: seen_window).ranked.limit(SIDEBAR_ONLINE_LIMIT).to_a
    roster = ([ viewer ] + roster).uniq.sort_by { |f| [ -f.belt, -f.xp, f.name ] }
    outbound = Fight.pending.where(challenger: viewer).pluck(:opponent_id).to_set
    inbound = Fight.pending.where(opponent: viewer).pluck(:challenger_id, :id).to_h
    now = Time.current

    roster.map do |fighter|
      state = if fighter.id == viewer.id then "you"
      elsif inbound.key?(fighter.id) then "respond"
      elsif outbound.include?(fighter.id) then "challenged"
      else "open"
      end
      online = fighter.id == viewer.id || fighter.online?
      row = fighter.presence_payload.merge(
        challenge_state: state, fight_id: inbound[fighter.id], online: online
      )
      unless online
        row[:offline_expires_in] = ((fighter.last_seen_at + seen_window) - now).to_i
      end
      row
    end
  end

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = User.find_by(id: session[:user_id])
  end

  # The signed-in user's fighter (nil when signed out). Every human has one via
  # User's after_create hook, so this is the entry point for all game actions.
  #
  # @return [Fighter, nil]
  def current_fighter
    current_user&.fighter
  end

  def signed_in?
    current_user.present?
  end

  def require_login
    redirect_to login_path, alert: "Sign in to continue." unless signed_in?
  end

  # Game actions require a signed-in user whose email is verified — the email is
  # the source of truth in this email-first app, so an unproven address can't
  # fight. Used by the challenge/fight controllers in Phase 2.
  def require_verified_fighter
    return if current_user&.email_verified?

    if signed_in?
      redirect_to root_path, alert: "Verify your email to step into the dojo — check your inbox for the link."
    else
      redirect_to login_path, alert: "Sign in to continue."
    end
  end

  # @param user [User]
  def sign_in(user)
    reset_session
    session[:user_id] = user.id
    @current_user = user
  end

  def sign_out
    reset_session
    @current_user = nil
  end
end
