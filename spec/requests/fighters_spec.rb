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

    it "hides declines — no column header and no count surfaced" do
      create(:fighter, name: "Chicken", declines: 12)

      get fighters_path

      expect(response.body).not_to include("Declines")
      expect(response.body).not_to match(/>\s*12\s*</)
    end

    it "offers a modal challenge opener per other fighter" do
      other = create(:fighter, name: "Target Dummy")

      get fighters_path

      expect(response.body).to include("data-challenge-open=\"#{other.id}\"")
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

    it "marks bots with a text [BOT] tag rather than an emoji" do
      bot = create(:fighter, :bot, name: "PixelSensei")

      get fighter_path(bot)

      expect(response.body).to include("PixelSensei")
      expect(response.body).to include("[BOT]")
      expect(response.body).not_to include("🤖")
    end

    it "hides declines on a profile" do
      other = create(:fighter, name: "No Shame", declines: 9)

      get fighter_path(other)

      expect(response.body).not_to include("Declines")
    end

    it "shows an Account panel with email + passkey manager on your own profile" do
      get fighter_path(user.fighter)

      expect(response.body).to include("Account")
      expect(response.body).to include(user.email)
      expect(response.body).to include("Your Passkeys").or include("Passkeys")
      expect(response.body).to include('data-passkey="add-credential"')
    end

    it "shows the challenge-alerts and preferences panels on your own profile" do
      get fighter_path(user.fighter)

      expect(response.body).to include("data-push-alerts")
      expect(response.body).to include("data-push-threshold")
      expect(response.body).to include("Allow challenges from bots")
    end

    it "shows no settings panels on someone else's profile" do
      other = create(:fighter, name: "Someone Else")

      get fighter_path(other)

      expect(response.body).not_to include("data-push-alerts")
      expect(response.body).not_to include("Allow challenges from bots")
    end

    it "shows no match history on your own profile — it lives on the homepage" do
      create(:fight, :resolved,
             challenger: user.fighter,
             opponent: create(:fighter, name: "Moved Away"),
             resolved_at: 1.hour.ago)

      get fighter_path(user.fighter)

      expect(response.body).not_to include("Match history")
    end

    it "shows no Account panel on someone else's profile" do
      other = create(:fighter, name: "Not You")

      get fighter_path(other)

      expect(response.body).not_to include("data-passkey=\"add-credential\"")
      expect(response.body).not_to include(user.email)
    end

    describe "match-history pagination (25 per page)" do
      let(:hero) { create(:fighter, name: "Marathon Master", belt: 5) }

      before do
        30.times do |i|
          create(:fight, :resolved,
                 challenger: hero,
                 opponent: create(:fighter, name: "Rival #{i}"),
                 resolved_at: i.hours.ago)
        end
      end

      it "shows the first 25 newest fights on page 1 with paging controls" do
        get fighter_path(hero)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Page 1 of 2")
        expect(response.body).to include("Rival 0")   # newest, on page 1
        expect(response.body).not_to include(">Rival 27<") # older, spills to page 2
      end

      it "shows the remaining fights on page 2" do
        get fighter_path(hero, page: 2)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Page 2 of 2")
        expect(response.body).to include("Rival 29") # oldest, on page 2
      end

      it "clamps an out-of-range page to the last page" do
        get fighter_path(hero, page: 99)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Page 2 of 2")
      end
    end
  end
end
