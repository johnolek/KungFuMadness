require "rails_helper"

RSpec.describe "Fighters", type: :request do
  let(:user) { create(:user) }

  before { sign_in_as(user) }

  describe "GET /fighters" do
    it "lists the roster ranked by belt then xp" do
      strong = create(:fighter, name: "Grand Master", belt: 7, xp: 6000)
      weak = create(:fighter, name: "Fresh Meat", belt: 1, xp: 0)

      get fighters_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(strong.name)
      expect(response.body).to include(weak.name)
      expect(response.body.index(strong.name)).to be < response.body.index(weak.name)
    end

    it "requires a verified fighter" do
      delete logout_path
      get fighters_path
      expect(response).to redirect_to(login_path)
    end
  end

  describe "GET /fighters/:id" do
    it "shows a profile with belt, record, and history" do
      other = create(:fighter, name: "Iron Fist", belt: 4, xp: 1600)

      get fighter_path(other)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Iron Fist")
      expect(response.body).to include("Match history")
      expect(response.body).to include("Challenge Iron Fist")
    end
  end
end
