class User < ApplicationRecord
  has_one :fighter, dependent: :destroy
  has_many :credentials, dependent: :destroy
  has_many :push_subscriptions, dependent: :destroy

  normalizes :email, with: ->(email) { email.strip.downcase.presence }

  validates :username, presence: true, uniqueness: true
  validates :webauthn_id, presence: true, uniqueness: true
  validates :email, presence: true, on: :create
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP },
                    uniqueness: { case_sensitive: false }, allow_nil: true

  # Signed, expiring token for the email magic-link sign-in. In this email-first
  # app the same link also proves the address on first use (see the sign-in
  # controller). Bound to the current email so changing it invalidates old links.
  generates_token_for :email_login, expires_in: 20.minutes do
    email
  end

  after_create :create_fighter

  # @return [Boolean] whether the current email address has been confirmed
  def email_verified?
    email_verified_at.present?
  end

  private

  # Every human gets a fighter that shares their username, starting as a fresh
  # white belt (belt index 1) with zero XP. Bots are created without a user.
  def create_fighter
    Fighter.create!(user: self, name: username, belt: 1, xp: 0)
  end
end
