require "rails_helper"

RSpec.describe ExpireChallengesJob, type: :job do
  let(:now) { Time.current }

  def pending_fight(expires_at:)
    create(:fight, status: :pending, expires_at: expires_at)
  end

  it "expires pending challenges past their deadline" do
    stale = pending_fight(expires_at: now - 1.hour)

    described_class.new.perform(now: now)

    expect(stale.reload).to be_expired
  end

  it "leaves pending challenges still inside their window alone" do
    fresh = pending_fight(expires_at: now + 1.day)

    described_class.new.perform(now: now)

    expect(fresh.reload).to be_pending
  end

  it "ignores fights that already resolved or declined" do
    resolved = create(:fight, :resolved, expires_at: now - 1.hour)

    described_class.new.perform(now: now)

    expect(resolved.reload).to be_resolved
  end

  it "notifies the challenger that their challenge expired" do
    broadcasts = []
    allow(ActionCable.server).to receive(:broadcast) { |stream, message| broadcasts << [ stream, message ] }
    fight = pending_fight(expires_at: now - 1.hour)

    described_class.new.perform(now: now)

    channel = FighterChannel.broadcasting_for(fight.challenger)
    message = broadcasts.select { |s, _| s == channel }.map(&:last).last
    expect(message).to be_present
    expect(message[:event]).to eq("challenge_expired")
  end
end
