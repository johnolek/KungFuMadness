class PreferencesController < ApplicationController
  before_action :require_verified_fighter

  def update
    current_user.update!(
      allow_bot_challenges: params[:allow_bot_challenges] == "1",
      hide_fight_spoilers: params[:hide_fight_spoilers] == "1"
    )
    redirect_to fighter_path(current_fighter), notice: "Preferences saved."
  end
end
