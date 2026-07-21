require "rails_helper"

RSpec.describe ApplicationCable::Connection, type: :channel do
  let(:session_key) { Rails.application.config.session_options.fetch(:key) }

  it "identifies a signed-in user from the encrypted session cookie" do
    user = create(:user)
    # The test cookie jar reads a Hash as cookie *options*, so the session hash
    # goes under :value to survive the round-trip.
    cookies.encrypted[session_key] = { value: { "user_id" => user.id } }

    connect

    expect(connection.current_user).to eq(user)
  end

  it "connects anonymously with no session cookie (public dojo spectating)" do
    connect

    expect(connection.current_user).to be_nil
  end

  it "connects anonymously when the session points at no user" do
    cookies.encrypted[session_key] = { value: { "user_id" => -1 } }

    connect

    expect(connection.current_user).to be_nil
  end
end
