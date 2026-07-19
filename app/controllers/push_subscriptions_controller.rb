class PushSubscriptionsController < ApplicationController
  before_action :require_verified_fighter

  # Register (or refresh) the browser's push subscription for the current user.
  # Keyed by endpoint so re-subscribing overwrites in place.
  def create
    subscription = PushSubscription.upsert_for(
      user: current_user,
      endpoint: params.require(:endpoint),
      p256dh_key: params.require(:keys).require(:p256dh),
      auth_key: params.require(:keys).require(:auth),
      user_agent: request.user_agent
    )

    if subscription.persisted?
      render json: { ok: true }
    else
      render json: { ok: false, errors: subscription.errors.full_messages }, status: :unprocessable_content
    end
  end

  # Drop the browser's subscription (the user opted out or unsubscribed).
  def destroy
    current_user.push_subscriptions.where(endpoint: params.require(:endpoint)).destroy_all
    render json: { ok: true }
  end
end
