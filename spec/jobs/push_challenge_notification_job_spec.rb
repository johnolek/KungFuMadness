require "rails_helper"

RSpec.describe PushChallengeNotificationJob, type: :job do
  def moves
    (1..3).map { |r| { round: r, attack_height: 2, attack_style: 0, block_height: 2 } }
  end

  def challenge(challenger:, opponent:)
    Fight.create_challenge!(challenger: challenger, opponent: opponent, moves: moves)
  end

  def expired_error
    response = Struct.new(:body).new("gone")
    WebPush::ExpiredSubscription.new(response, "push.example.com")
  end

  let(:challenger) { create(:fighter, name: "PepsiDad", belt: 3, xp: 800) }
  let(:opponent_user) { create(:user) }
  let(:opponent) { opponent_user.fighter }

  before { allow(WebPush).to receive(:payload_send) }

  it "delivers one notification per subscription of the opponent's user" do
    create(:push_subscription, user: opponent_user)
    create(:push_subscription, user: opponent_user)
    fight = challenge(challenger: challenger, opponent: opponent)

    described_class.perform_now(fight.id)

    expect(WebPush).to have_received(:payload_send).twice
  end

  it "builds a body naming the challenger and their snapshot belt" do
    create(:push_subscription, user: opponent_user)
    fight = challenge(challenger: challenger, opponent: opponent)

    described_class.perform_now(fight.id)

    expect(WebPush).to have_received(:payload_send).with(
      hash_including(message: a_string_including("PepsiDad", Belt.name_for(fight.challenger_belt), "challenges you"))
    )
  end

  it "does nothing when the opponent has no subscriptions" do
    fight = challenge(challenger: challenger, opponent: opponent)

    described_class.perform_now(fight.id)

    expect(WebPush).not_to have_received(:payload_send)
  end

  it "prunes gone subscriptions as it delivers" do
    create(:push_subscription, user: opponent_user)
    allow(WebPush).to receive(:payload_send).and_raise(expired_error)
    fight = challenge(challenger: challenger, opponent: opponent)

    expect { described_class.perform_now(fight.id) }
      .to change { PushSubscription.where(user: opponent_user).count }.from(1).to(0)
  end

  it "no-ops cleanly on a missing fight" do
    expect { described_class.perform_now(-1) }.not_to raise_error
    expect(WebPush).not_to have_received(:payload_send)
  end

  describe "minimum pending challenges threshold" do
    before { create(:push_subscription, user: opponent_user) }

    it "holds the push while pending challenges are below the user's threshold" do
      opponent_user.update!(push_min_pending_challenges: 3)
      fight = challenge(challenger: challenger, opponent: opponent)

      described_class.perform_now(fight.id)

      expect(WebPush).not_to have_received(:payload_send)
    end

    it "delivers once pending challenges reach the threshold" do
      opponent_user.update!(push_min_pending_challenges: 3)
      challenge(challenger: challenger, opponent: opponent)
      challenge(challenger: create(:fighter, name: "Iron Palm"), opponent: opponent)
      fight = challenge(challenger: create(:fighter, name: "Silent Crane"), opponent: opponent)

      described_class.perform_now(fight.id)

      expect(WebPush).to have_received(:payload_send).once
    end

    it "counts only still-pending challenges toward the threshold" do
      opponent_user.update!(push_min_pending_challenges: 2)
      declined = challenge(challenger: create(:fighter, name: "Iron Palm"), opponent: opponent)
      declined.decline!
      fight = challenge(challenger: challenger, opponent: opponent)

      described_class.perform_now(fight.id)

      expect(WebPush).not_to have_received(:payload_send)
    end
  end
end
