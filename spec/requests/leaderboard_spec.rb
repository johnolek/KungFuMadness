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

    it "surfaces the most active fighters of the last seven days" do
      grinder = create(:fighter, name: "Busy Bee")
      opponent = create(:fighter, name: "Sparring Partner")
      create(:fight, :resolved, challenger: grinder, opponent: opponent, resolved_at: 1.day.ago)
      create(:fight, :resolved, challenger: opponent, opponent: grinder, resolved_at: 8.days.ago)

      get leaderboard_path

      expect(response.body).to include("Most active this week")
      expect(response.body).to include("Busy Bee")
    end

    it "requires a verified fighter" do
      delete logout_path
      get leaderboard_path
      expect(response).to redirect_to(login_path)
    end
  end
end
