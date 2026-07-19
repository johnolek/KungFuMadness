class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :current_user, :current_fighter, :signed_in?

  private

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
