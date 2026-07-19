require "rails_helper"

RSpec.describe DojoChannel, type: :channel do
  let(:user) { create(:user) }
  let(:fighter) { user.fighter }

  it "confirms, streams the dojo, and stamps presence on subscribe" do
    stub_connection current_user: user
    fighter.update_column(:last_seen_at, 10.minutes.ago)

    subscribe

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from(DojoChannel::STREAM)
    expect(fighter.reload.last_seen_at).to be_within(2.seconds).of(Time.current)
  end

  it "announces the fighter online to the dojo on subscribe" do
    stub_connection current_user: user

    expect { subscribe }
      .to have_broadcasted_to(DojoChannel::STREAM)
      .with(hash_including(event: "presence", online: true))
  end

  it "announces the fighter offline to the dojo on unsubscribe" do
    stub_connection current_user: user
    subscribe

    expect { unsubscribe }
      .to have_broadcasted_to(DojoChannel::STREAM)
      .with(hash_including(event: "presence", online: false))
  end

  it "refreshes last_seen_at on a ping" do
    stub_connection current_user: user
    subscribe
    fighter.update_column(:last_seen_at, 10.minutes.ago)

    perform :ping

    expect(fighter.reload.last_seen_at).to be_within(2.seconds).of(Time.current)
  end
end
