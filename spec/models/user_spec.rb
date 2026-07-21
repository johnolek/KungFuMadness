require "rails_helper"

RSpec.describe User, type: :model do
  subject { create(:user) }

  it { is_expected.to validate_presence_of(:username) }
  it { is_expected.to validate_presence_of(:webauthn_id) }
  it { is_expected.to have_one(:fighter).dependent(:destroy) }
  it { is_expected.to have_many(:credentials).dependent(:destroy) }

  it "requires a unique username (case-insensitive)" do
    create(:user, username: "Alice")
    expect(build(:user, username: "alice")).not_to be_valid
  end

  it "requires a unique webauthn_id" do
    existing = create(:user)
    expect(build(:user, webauthn_id: existing.webauthn_id)).not_to be_valid
  end

  it "normalizes email to stripped lowercase" do
    user = create(:user, email: "  MixedCase@Example.COM ")
    expect(user.email).to eq("mixedcase@example.com")
  end

  it "requires an email on create" do
    expect(build(:user, email: nil)).not_to be_valid
  end

  describe "push_min_pending_challenges" do
    it "defaults to 3" do
      expect(subject.push_min_pending_challenges).to eq(3)
    end

    it "allows 1 through 1000" do
      expect(build(:user, push_min_pending_challenges: 1)).to be_valid
      expect(build(:user, push_min_pending_challenges: 1000)).to be_valid
      expect(build(:user, push_min_pending_challenges: 0)).not_to be_valid
      expect(build(:user, push_min_pending_challenges: 1001)).not_to be_valid
      expect(build(:user, push_min_pending_challenges: 2.5)).not_to be_valid
    end
  end

  describe "email verification state" do
    it "starts unverified" do
      expect(subject.email_verified?).to be(false)
    end

    it "reports verified once email_verified_at is set" do
      subject.update!(email_verified_at: Time.current)
      expect(subject.email_verified?).to be(true)
    end
  end

  describe "email_login token" do
    it "signs in the matching user" do
      token = subject.generate_token_for(:email_login)
      expect(User.find_by_token_for(:email_login, token)).to eq(subject)
    end

    it "is invalidated by an email change" do
      token = subject.generate_token_for(:email_login)
      subject.update!(email: "new-address@example.com")
      expect(User.find_by_token_for(:email_login, token)).to be_nil
    end
  end

  describe "fighter auto-creation" do
    let(:user) { create(:user, username: "IronFist") }

    it "creates a fighter named after the user, white belt, zero XP" do
      fighter = user.fighter
      expect(fighter).to be_present
      expect(fighter.name).to eq("IronFist")
      expect(fighter.belt).to eq(1)
      expect(fighter.xp).to eq(0)
      expect(fighter.bot).to be(false)
    end
  end
end
