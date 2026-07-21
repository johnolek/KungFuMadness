require "rails_helper"

RSpec.describe "PushSettings", type: :request do
  let(:user) { create(:user) }

  describe "PATCH /push_settings" do
    context "as a verified fighter" do
      before { sign_in_as(user) }

      it "updates the minimum pending challenges threshold" do
        patch push_settings_path, params: { min_pending_challenges: 5 }, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["min_pending_challenges"]).to eq(5)
        expect(user.reload.push_min_pending_challenges).to eq(5)
      end

      it "rejects a threshold below 1" do
        patch push_settings_path, params: { min_pending_challenges: 0 }, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(user.reload.push_min_pending_challenges).to eq(3)
      end

      it "rejects a threshold above 1000" do
        patch push_settings_path, params: { min_pending_challenges: 1001 }, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(user.reload.push_min_pending_challenges).to eq(3)
      end
    end

    context "when signed out" do
      it "does not change anything" do
        patch push_settings_path, params: { min_pending_challenges: 5 }, as: :json

        expect(response).to have_http_status(:redirect)
        expect(user.reload.push_min_pending_challenges).to eq(3)
      end
    end
  end
end
