class ProfilesController < ApplicationController
  before_action :require_verified_fighter

  # Own-profile customization: portrait + short bio. Avatar is assigned (not
  # attach!ed) so the model validations gate the save.
  def update
    fighter = current_fighter
    fighter.bio = params[:bio].to_s.strip.presence
    fighter.avatar.purge_later if params[:remove_avatar] == "1"
    fighter.avatar = params[:avatar] if params[:avatar].present?

    if fighter.save
      redirect_to fighter_path(fighter), notice: "Profile updated."
    else
      redirect_to fighter_path(fighter), alert: fighter.errors.full_messages.to_sentence
    end
  end
end
