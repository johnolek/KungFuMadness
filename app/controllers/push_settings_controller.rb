class PushSettingsController < ApplicationController
  before_action :require_verified_fighter

  # Update the current user's push preferences (today just the minimum pending
  # challenges before a notification fires). JSON in/out, like push_subscriptions.
  def update
    if current_user.update(push_min_pending_challenges: params.require(:min_pending_challenges))
      render json: { ok: true, min_pending_challenges: current_user.push_min_pending_challenges }
    else
      render json: { ok: false, errors: current_user.errors.full_messages }, status: :unprocessable_content
    end
  end
end
