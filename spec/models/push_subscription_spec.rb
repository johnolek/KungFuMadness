require "rails_helper"

RSpec.describe PushSubscription, type: :model do
  # A gone-subscription error as web-push raises it (404/410). ResponseError needs
  # a response object it can inspect and read a body from.
  def expired_error
    response = Struct.new(:body).new("gone")
    WebPush::ExpiredSubscription.new(response, "push.example.com")
  end

  describe ".upsert_for" do
    let(:user) { create(:user) }

    it "creates a subscription keyed by its endpoint" do
      expect {
        described_class.upsert_for(
          user: user,
          endpoint: "https://push.example.com/abc",
          p256dh_key: "p256",
          auth_key: "auth",
          user_agent: "Test/1.0"
        )
      }.to change(described_class, :count).by(1)

      sub = described_class.last
      expect(sub.user).to eq(user)
      expect(sub.p256dh_key).to eq("p256")
      expect(sub.user_agent).to eq("Test/1.0")
    end

    it "refreshes an existing endpoint in place rather than duplicating it" do
      described_class.upsert_for(user: user, endpoint: "https://push.example.com/abc",
                                 p256dh_key: "old", auth_key: "old-auth")

      expect {
        described_class.upsert_for(user: user, endpoint: "https://push.example.com/abc",
                                   p256dh_key: "new", auth_key: "new-auth")
      }.not_to change(described_class, :count)

      expect(described_class.find_by(endpoint: "https://push.example.com/abc").p256dh_key).to eq("new")
    end
  end

  describe "#deliver" do
    let(:subscription) { create(:push_subscription) }

    it "sends the payload through WebPush with the app's VAPID details" do
      allow(WebPush).to receive(:payload_send)

      expect(subscription.deliver({ title: "New challenge!" })).to be(true)

      expect(WebPush).to have_received(:payload_send).with(
        hash_including(
          endpoint: subscription.endpoint,
          p256dh: subscription.p256dh_key,
          auth: subscription.auth_key,
          vapid: Push.vapid_details
        )
      )
    end

    it "prunes itself and returns false when the subscription is gone" do
      allow(WebPush).to receive(:payload_send).and_raise(expired_error)
      subscription

      expect { expect(subscription.deliver("{}")).to be(false) }
        .to change(described_class, :count).by(-1)
    end
  end
end
