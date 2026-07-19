require "rails_helper"

RSpec.describe "PushSubscriptions", type: :request do
  let(:user) { create(:user) }

  let(:subscription_params) do
    {
      endpoint: "https://push.example.com/endpoint/xyz",
      keys: { p256dh: "BExampleKey", auth: "authsecret" }
    }
  end

  describe "POST /push_subscriptions" do
    context "as a verified fighter" do
      before { sign_in_as(user) }

      it "registers the subscription for the current user" do
        expect {
          post push_subscriptions_path, params: subscription_params, as: :json
        }.to change(user.push_subscriptions, :count).by(1)

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["ok"]).to be(true)

        sub = user.push_subscriptions.last
        expect(sub.endpoint).to eq(subscription_params[:endpoint])
        expect(sub.p256dh_key).to eq("BExampleKey")
        expect(sub.auth_key).to eq("authsecret")
      end

      it "upserts by endpoint instead of duplicating" do
        post push_subscriptions_path, params: subscription_params, as: :json

        expect {
          post push_subscriptions_path, params: subscription_params, as: :json
        }.not_to change(PushSubscription, :count)
      end
    end

    context "when signed out" do
      it "does not create a subscription" do
        expect {
          post push_subscriptions_path, params: subscription_params, as: :json
        }.not_to change(PushSubscription, :count)

        expect(response).to have_http_status(:redirect)
      end
    end
  end

  describe "DELETE /push_subscriptions" do
    before { sign_in_as(user) }

    it "removes the current user's subscription by endpoint" do
      create(:push_subscription, user: user, endpoint: subscription_params[:endpoint])

      expect {
        delete push_subscriptions_path, params: { endpoint: subscription_params[:endpoint] }, as: :json
      }.to change(user.push_subscriptions, :count).by(-1)

      expect(response).to have_http_status(:ok)
    end

    it "leaves another user's subscription untouched" do
      other = create(:push_subscription, endpoint: subscription_params[:endpoint])

      delete push_subscriptions_path, params: { endpoint: subscription_params[:endpoint] }, as: :json

      expect(PushSubscription.exists?(other.id)).to be(true)
    end
  end
end
