class FightsController < ApplicationController
  # Resolved fights are public to anyone (spectating + scouting — the sidebar
  # links here for signed-out visitors too). A still-pending fight isn't a
  # spectacle: only its two participants may peek, and only at minimal state —
  # the sealed moves never surface here.
  def show
    @fight = Fight.find(params[:id])

    if @fight.resolved?
      @payload = @fight.playback_payload
      @reveal = claim_first_own_view
      return
    end

    participant = [ @fight.challenger, @fight.opponent ].include?(current_fighter)
    unless participant
      redirect_to root_path, alert: "That fight hasn't happened yet." and return
    end

    render :pending
  end

  private

  # The round-by-round reveal is reserved for the first time a participant views
  # their own settled fight; spectators and repeat visits get everything at once.
  # Stamps the viewer's side as seen so the drama only plays once.
  #
  # @return [Boolean] whether this request should step through the rounds
  def claim_first_own_view
    column =
      if current_fighter == @fight.challenger then :challenger_seen_at
      elsif current_fighter == @fight.opponent then :opponent_seen_at
      end
    return false if column.nil? || @fight[column].present?

    @fight.update_column(column, Time.current)
    true
  end
end
