class ChallengesController < ApplicationController
  before_action :require_verified_fighter

  # How many of an opponent's recent fights the scouting panel surfaces.
  SCOUT_FIGHTS = 8

  # Pick moves against a chosen opponent. ?opponent=ID selects the target. The
  # HTML page is the no-JS fallback; the .json variant feeds the challenge modal.
  def new
    @opponent = Fighter.find(params[:opponent])
    if @opponent == current_fighter
      respond_to do |format|
        format.html { redirect_to fighters_path, alert: "You can't challenge yourself." }
        format.json { render json: { error: "You can't challenge yourself." }, status: :unprocessable_content }
      end
      return
    end

    @fighter = current_fighter
    @scout = @opponent
    @recent_fights = scout_fights(@opponent)

    respond_to do |format|
      format.html
      format.json { render json: challenge_modal_payload(@opponent) }
    end
  end

  # Commit the challenger's three rounds and seal the challenge.
  def create
    opponent = Fighter.find(params[:opponent])
    fight = Fight.create_challenge!(
      challenger: current_fighter,
      opponent: opponent,
      moves: parsed_moves
    )
    enqueue_bot_response(fight)
    respond_to do |format|
      format.html { redirect_to fighter_path(opponent), notice: "Challenge sent to #{opponent.name}. The waiting begins." }
      format.json { render json: { ok: true, opponent_id: opponent.id, message: "Challenge sent to #{opponent.name}.", card: fight.challenge_card_payload } }
    end
  rescue Fight::ChallengeError => e
    respond_to do |format|
      format.html { redirect_to fighter_path(params[:opponent]), alert: e.message }
      format.json { render json: { error: e.message }, status: :unprocessable_content }
    end
  rescue JSON::ParserError, KeyError, ArgumentError
    respond_to do |format|
      format.html { redirect_to new_challenge_path(opponent: params[:opponent]), alert: "Those moves didn't make sense — try again." }
      format.json { render json: { error: "Those moves didn't make sense — try again." }, status: :unprocessable_content }
    end
  end

  # The respond page. Only the opponent may commit moves here; the challenger
  # sees a read-only "waiting" state; everyone else is turned away. The .json
  # variant feeds the respond modal and is opponent-only.
  def show
    @fight = Fight.find(params[:id])
    return render_respond_json if request.format.json?

    if @fight.resolved? || @fight.declined? || @fight.expired?
      redirect_to fight_path(@fight) and return if @fight.resolved?

      redirect_to root_path, alert: "That challenge is no longer open." and return
    end

    @viewer_role = viewer_role_for(@fight)
    redirect_to root_path, alert: "That challenge isn't yours to answer." and return if @viewer_role == :stranger

    # Scout the other party: the responder sizes up the challenger, the waiting
    # challenger sizes up the opponent. Only ever their public resolved history —
    # never the sealed moves of THIS pending fight.
    @scout = @viewer_role == :opponent ? @fight.challenger : @fight.opponent
    @recent_fights = scout_fights(@scout)
  end

  # Opponent accepts: commit moves, resolve, go watch it.
  def accept
    @fight = Fight.find(params[:id])
    unless @fight.opponent == current_fighter
      return deny("That challenge isn't yours to answer.")
    end

    if @fight.respond!(moves: parsed_moves)
      respond_to do |format|
        format.html { redirect_to fight_path(@fight), notice: "The fight is settled." }
        format.json { render json: { ok: true, redirect_url: fight_path(@fight) } }
      end
    else
      deny("That challenge could not be answered — it may have expired.")
    end
  rescue JSON::ParserError, KeyError, ArgumentError
    respond_to do |format|
      format.html { redirect_to challenge_path(@fight), alert: "Those moves didn't make sense — try again." }
      format.json { render json: { error: "Those moves didn't make sense — try again." }, status: :unprocessable_content }
    end
  end

  # Opponent declines.
  def decline
    @fight = Fight.find(params[:id])
    unless @fight.opponent == current_fighter
      return deny("That challenge isn't yours to decline.")
    end

    if @fight.decline!
      respond_to do |format|
        format.html { redirect_to root_path, notice: "You turned down the challenge." }
        format.json { render json: { ok: true, message: "You turned down the challenge." } }
      end
    else
      deny("That challenge could not be declined.")
    end
  end

  private

  # Uniform "not for you / no longer open" refusal for both HTML and modal callers.
  def deny(message)
    respond_to do |format|
      format.html { redirect_to root_path, alert: message }
      format.json { render json: { error: message }, status: :unprocessable_content }
    end
  end

  # Payload for the challenge modal: who you're facing plus their compact scouting
  # table. Keeps sealed discipline trivially — the target has no bearing on any
  # pending challenge's moves.
  def challenge_modal_payload(opponent)
    {
      mode: "challenge",
      action: challenges_path,
      opponent: fighter_card(opponent, belt: opponent.belt),
      scouting: scout_payload(opponent),
      tendency: tendency_payload(opponent)
    }
  end

  # Payload for the respond modal. Opponent-only, pending-only, and carries ZERO
  # challenger move data — the responder scouts the challenger's public history,
  # never the sealed moves of this fight.
  def render_respond_json
    if @fight.opponent != current_fighter || !@fight.pending?
      return render json: { error: "That challenge isn't open to you." }, status: :forbidden
    end

    render json: {
      mode: "respond",
      fight_id: @fight.id,
      accept_url: accept_challenge_path(@fight),
      decline_url: decline_challenge_path(@fight),
      opponent: fighter_card(@fight.challenger, belt: @fight.challenger_belt),
      scouting: scout_payload(@fight.challenger),
      tendency: tendency_payload(@fight.challenger)
    }
  end

  # Opponent/challenger summary for a modal header. NO declines (hidden mechanic).
  def fighter_card(fighter, belt:)
    {
      id: fighter.id,
      name: fighter.name,
      display_name: fighter.display_name,
      belt: belt,
      belt_name: Belt.name_for(belt),
      bot: fighter.bot,
      record: "#{fighter.wins}-#{fighter.losses}-#{fighter.draws}",
      url: fighter_path(fighter)
    }
  end

  # Compact tendency strip for the modal — overall attack/block height splits over
  # the fighter's full resolved history. Nil when there's nothing to read yet.
  def tendency_payload(fighter)
    Scouting.new(fighter: fighter).strip_summary
  end

  # Compact last-N resolved fights from +fighter+'s perspective for modal scouting.
  def scout_payload(fighter)
    scout_fights(fighter).map do |fight|
      as_challenger = fight.challenger_id == fighter.id
      other = as_challenger ? fight.opponent : fight.challenger
      other_belt = as_challenger ? fight.opponent_belt : fight.challenger_belt
      result = if fight.winner_id.nil? then "draw"
      elsif fight.winner_id == fighter.id then "win"
      else "loss"
      end
      {
        id: fight.id,
        date: fight.resolved_at.strftime("%Y-%m-%d"),
        opponent_name: other.display_name,
        opponent_belt: other_belt,
        result: result,
        ko: fight.ko,
        url: fight_path(fight)
      }
    end
  end

  # A fighter's most recent resolved fights for the scouting panel.
  def scout_fights(fighter)
    fighter.resolved_fights.includes(:challenger, :opponent).limit(SCOUT_FIGHTS)
  end

  def viewer_role_for(fight)
    return :opponent if fight.opponent == current_fighter
    return :challenger if fight.challenger == current_fighter

    :stranger
  end

  # Moves arrive as a JSON string (the MoveCommitter form's hidden field) or as a
  # parsed array (the modal's fetch body). Fight#normalize_moves does the
  # per-field coercion either way.
  def parsed_moves
    raw = params.fetch(:moves)
    raw.is_a?(String) ? JSON.parse(raw) : raw
  end

  # In dev, resolve bot challenges shortly after they're issued so the loop feels
  # alive without a running scheduler. Off in production, where Bots::TickJob is
  # the real cadence — bots answer only while "online" (config.x.bots.immediate_response).
  def enqueue_bot_response(fight)
    return unless Rails.application.config.x.bots.immediate_response
    return unless fight.opponent.bot?

    Bots::RespondJob.set(wait: rand(2..8).seconds).perform_later(fight.id)
  end
end
