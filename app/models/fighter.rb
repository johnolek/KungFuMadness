class Fighter < ApplicationRecord
  belongs_to :user, optional: true

  has_many :challenges_made, class_name: "Fight", foreign_key: :challenger_id, dependent: :destroy, inverse_of: :challenger
  has_many :challenges_received, class_name: "Fight", foreign_key: :opponent_id, dependent: :destroy, inverse_of: :opponent
  has_many :fight_moves, dependent: :destroy

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :xp, :belt, :wins, :losses, :draws, :declines,
            presence: true, numericality: { only_integer: true }
  validates :belt, numericality: { greater_than_or_equal_to: 0 }
  validates :user_id, uniqueness: true, allow_nil: true

  scope :bots, -> { where(bot: true) }
  scope :humans, -> { where(bot: false) }
  scope :online, ->(within: 2.minutes) { where(last_seen_at: within.ago..) }
  # Leaderboard order: strongest belt first, then XP within the belt.
  scope :ranked, -> { order(belt: :desc, xp: :desc, name: :asc) }

  # @return [String] the display name of the fighter's current belt
  def belt_name
    Belt.name_for(belt)
  end

  # Plain-text display name — bots carry a "[BOT]" suffix so they read as bots
  # wherever HTML styling isn't available (Svelte props, payloads, page titles).
  # HTML views should prefer the +fighter_display_name+ helper, which dims the tag.
  #
  # @return [String]
  def display_name
    bot? ? "#{name} [BOT]" : name
  end

  # @return [Boolean] whether the fighter is currently in the sub-white Tofu belt
  def tofu?
    belt.zero?
  end

  # @return [String] compact win-loss-draw record, e.g. "12-4-1"
  def record
    "#{wins}-#{losses}-#{draws}"
  end

  # Resolved fights this fighter took part in, newest first — the public,
  # scoutable match history.
  #
  # @return [ActiveRecord::Relation<Fight>]
  def resolved_fights
    Fight.resolved.for_fighter(self).order(resolved_at: :desc)
  end

  # Pending challenges waiting on THIS fighter to respond.
  #
  # @return [ActiveRecord::Relation<Fight>]
  def incoming_challenges
    Fight.pending.where(opponent: self).order(created_at: :desc)
  end

  # Pending challenges this fighter has sent and is waiting on.
  #
  # @return [ActiveRecord::Relation<Fight>]
  def outgoing_challenges
    Fight.pending.where(challenger: self).order(created_at: :desc)
  end

  # Identity slice shared by the online sidebar and presence events. Just enough
  # to render a row and link to the profile — never any private state.
  #
  # @return [Hash]
  def presence_payload
    {
      id: id,
      name: name,
      display_name: display_name,
      belt: belt,
      belt_name: belt_name,
      bot: bot,
      url: Rails.application.routes.url_helpers.fighter_path(self)
    }
  end
end
