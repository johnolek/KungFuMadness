require "rails_helper"

RSpec.describe "Leaderboard", type: :request do
  let(:user) { create(:user) }

  before { sign_in_as(user) }

  describe "GET /leaderboard" do
    it "ranks fighters by all-time XP, humans and bots together" do
      leader = create(:fighter, name: "Apex Tiger", xp: 9000, belt: 7)
      bot = create(:fighter, :bot, name: "Silicon Crane", xp: 5000, belt: 5)
      rookie = create(:fighter, name: "Green Sprout", xp: 100, belt: 1)

      get leaderboard_path

      expect(response).to have_http_status(:ok)
      [ leader, bot, rookie ].each { |f| expect(response.body).to include(f.name) }
      expect(response.body).to include("[BOT]")
      expect(response.body.index(leader.name)).to be < response.body.index(rookie.name)
    end

    it "no longer surfaces a most-active board" do
      get leaderboard_path

      expect(response.body).not_to include("Most active this week")
    end

    it "is public to signed-out visitors" do
      delete logout_path
      get leaderboard_path
      expect(response).to have_http_status(:ok)
    end
  end
end
