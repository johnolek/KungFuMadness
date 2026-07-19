class FightsController < ApplicationController
  before_action :require_verified_fighter

  # Resolved fights are public to any verified fighter (spectating + scouting).
  # A still-pending fight isn't a spectacle: only its two participants may peek,
  # and only at minimal state — the sealed moves never surface here.
  def show
    @fight = Fight.find(params[:id])

    if @fight.resolved?
      @payload = @fight.playback_payload
      return
    end

    participant = [ @fight.challenger, @fight.opponent ].include?(current_fighter)
    unless participant
      redirect_to root_path, alert: "That fight hasn't happened yet." and return
    end

    render :pending
  end
end
