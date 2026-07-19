require "rails_helper"

RSpec.describe FighterChannel, type: :channel do
  let(:user) { create(:user) }

  it "streams for the subscriber's own fighter" do
    stub_connection current_user: user

    subscribe

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_for(user.fighter)
  end

  it "does not stream for anyone else's fighter" do
    stub_connection current_user: user
    other = create(:fighter, name: "Someone Else")

    subscribe

    expect(subscription).not_to have_stream_for(other)
  end
end
