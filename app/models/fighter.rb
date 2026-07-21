class Fighter < ApplicationRecord
  AVATAR_CONTENT_TYPES = %w[image/png image/jpeg image/webp image/gif].freeze
  AVATAR_MAX_BYTES = 2.megabytes
  BIO_MAX_LENGTH = 200

  belongs_to :user, optional: true

  has_many :challenges_made, class_name: "Fight", foreign_key: :challenger_id, dependent: :destroy, inverse_of: :challenger
  has_many :challenges_received, class_name: "Fight", foreign_key: :opponent_id, dependent: :destroy, inverse_of: :opponent
  has_many :fight_moves, dependent: :destroy
  has_one_attached :avatar

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :xp, :belt, :wins, :losses, :draws, :declines,
            presence: true, numericality: { only_integer: true }
  validates :belt, numericality: { greater_than_or_equal_to: 0 }
  validates :user_id, uniqueness: true, allow_nil: true
  validates :bio, length: { maximum: BIO_MAX_LENGTH }, allow_nil: true
  validate :avatar_within_limits

  # How recently last_seen_at must have been stamped for a fighter to count as
  # "online". The DojoChannel ping loop and the bot tick both refresh within this
  # window; it's the single source of truth for presence.
  ONLINE_WINDOW = 2.minutes

  # How long past the online window a fighter still lingers in the sidebar as
  # "recently offline" — dimmed but challengeable, in case they have push
  # notifications on.
  RECENT_OFFLINE_GRACE = 5.minutes

  scope :bots, -> { where(bot: true) }
  scope :humans, -> { where(bot: false) }
  scope :online, ->(within: ONLINE_WINDOW) { where(last_seen_at: within.ago..) }
  # Everyone except humans whose user switched bot challenges off. Humans with no
  # user row (test fixtures) have no join match, so they stay in.
  scope :accepting_bot_challenges, -> {
    where.not(id: humans.joins(:user).where(users: { allow_bot_challenges: false }).select(:id))
  }

  # Any settled belt change — through a fight, through rust decay — announces
  # itself to the dojo ticker on commit, so promotions and demotions read the same
  # wherever they come from. On commit so a rolled-back settlement stays silent.
  after_update_commit :broadcast_belt_change, if: :saved_change_to_belt?
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

  # @return [Boolean] whether bots may open challenges against this fighter
  def accepts_bot_challenges?
    bot? || user.nil? || user.allow_bot_challenges
  end

  # @return [Boolean] whether the fighter was seen inside the online window
  def online?
    last_seen_at.present? && last_seen_at >= ONLINE_WINDOW.ago
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

  private

  def broadcast_belt_change
    from, _to = saved_change_to_belt
    DojoChannel.broadcast_belt_change(self, from: from)
  end

  def avatar_within_limits
    return unless avatar.attached?

    unless AVATAR_CONTENT_TYPES.include?(avatar.content_type)
      errors.add(:avatar, "must be a PNG, JPEG, WebP, or GIF image")
    end
    errors.add(:avatar, "must be 2MB or smaller") if avatar.blob.byte_size > AVATAR_MAX_BYTES
  end
end
