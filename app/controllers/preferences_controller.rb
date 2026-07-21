class PreferencesController < ApplicationController
  before_action :require_verified_fighter

  def update
    allow = params[:allow_bot_challenges] == "1"
    current_user.update!(allow_bot_challenges: allow)
    notice = allow ? "Bots may challenge you." : "Bots will no longer challenge you."
    redirect_to root_path, notice: notice
  end
end
