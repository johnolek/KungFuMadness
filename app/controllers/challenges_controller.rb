class ChallengesController < ApplicationController
  before_action :require_verified_fighter

  # Pick moves against a chosen opponent. ?opponent=ID selects the target.
  def new
    @opponent = Fighter.find(params[:opponent])
    if @opponent == current_fighter
      redirect_to fighters_path, alert: "You can't challenge yourself." and return
    end
    @fighter = current_fighter
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
    redirect_to fighter_path(opponent), notice: "Challenge sent to #{opponent.name}. The waiting begins."
  rescue Fight::ChallengeError => e
    redirect_to fighter_path(params[:opponent]), alert: e.message
  rescue JSON::ParserError, KeyError, ArgumentError
    redirect_to new_challenge_path(opponent: params[:opponent]), alert: "Those moves didn't make sense — try again."
  end

  # The respond page. Only the opponent may commit moves here; the challenger
  # sees a read-only "waiting" state; everyone else is turned away.
  def show
    @fight = Fight.find(params[:id])

    if @fight.resolved? || @fight.declined? || @fight.expired?
      redirect_to fight_path(@fight) and return if @fight.resolved?

      redirect_to root_path, alert: "That challenge is no longer open." and return
    end

    @viewer_role = viewer_role_for(@fight)
    redirect_to root_path, alert: "That challenge isn't yours to answer." and return if @viewer_role == :stranger
  end

  # Opponent accepts: commit moves, resolve, go watch it.
  def accept
    @fight = Fight.find(params[:id])
    unless @fight.opponent == current_fighter
      redirect_to root_path, alert: "That challenge isn't yours to answer." and return
    end

    if @fight.respond!(moves: parsed_moves)
      redirect_to fight_path(@fight), notice: "The fight is settled."
    else
      redirect_to root_path, alert: "That challenge could not be answered — it may have expired."
    end
  rescue JSON::ParserError, KeyError, ArgumentError
    redirect_to challenge_path(@fight), alert: "Those moves didn't make sense — try again."
  end

  # Opponent declines.
  def decline
    @fight = Fight.find(params[:id])
    unless @fight.opponent == current_fighter
      redirect_to root_path, alert: "That challenge isn't yours to decline." and return
    end

    if @fight.decline!
      redirect_to root_path, notice: "You turned down the challenge."
    else
      redirect_to root_path, alert: "That challenge could not be declined."
    end
  end

  private

  def viewer_role_for(fight)
    return :opponent if fight.opponent == current_fighter
    return :challenger if fight.challenger == current_fighter

    :stranger
  end

  # Moves arrive as a JSON string in a hidden form field committed by the
  # MoveCommitter island. Fight#normalize_moves does the per-field coercion.
  def parsed_moves
    JSON.parse(params.fetch(:moves))
  end

  # In dev, resolve bot challenges shortly after they're issued so the loop feels
  # alive without a running scheduler. Recurring bot ticks arrive in Phase 4.
  def enqueue_bot_response(fight)
    return unless fight.opponent.bot?

    Bots::RespondJob.set(wait: rand(2..8).seconds).perform_later(fight.id)
  end
end
