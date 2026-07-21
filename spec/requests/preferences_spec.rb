require "rails_helper"

RSpec.describe "Preferences", type: :request do
  let(:user) { create(:user) }

  describe "PATCH /preferences" do
    context "as a verified fighter" do
      before { sign_in_as(user) }

      it "turns bot challenges off and returns to the profile" do
        patch preferences_path, params: { allow_bot_challenges: "0" }

        expect(response).to redirect_to(fighter_path(user.fighter))
        expect(user.reload.allow_bot_challenges).to be(false)
      end

      it "turns bot challenges back on" do
        user.update!(allow_bot_challenges: false)

        patch preferences_path, params: { allow_bot_challenges: "1" }

        expect(user.reload.allow_bot_challenges).to be(true)
      end
    end

    context "when signed out" do
      it "changes nothing" do
        patch preferences_path, params: { allow_bot_challenges: "0" }

        expect(response).to have_http_status(:redirect)
        expect(user.reload.allow_bot_challenges).to be(true)
      end
    end
  end
end
