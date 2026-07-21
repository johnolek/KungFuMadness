require "rails_helper"

RSpec.describe "Dojo", type: :request do
  describe "GET /" do
    it "renders a signed-out intro with join links" do
      get root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("The Dojo")
      expect(response.body).to include(signup_path)
    end

    it "shows a verified fighter their living-world layout: inbox + sidebar islands" do
      user = create(:user)
      sign_in_as(user)

      get root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Welcome back")
      expect(response.body).to include('data-svelte-component="Inbox"')
      expect(response.body).to include('data-svelte-component="RecentFightsSidebar"')
      expect(response.body).to include('data-svelte-component="OnlineSidebar"')
      expect(response.body).to include('data-svelte-component="ChallengeModal"')
    end

    it "emits the VAPID meta tag and the challenge-alerts opt-in panel for a verified fighter" do
      user = create(:user)
      sign_in_as(user)

      get root_path

      expect(response.body).to include('name="vapid-public-key"')
      expect(response.body).to include(Push.public_key)
      expect(response.body).to include("data-push-alerts")
      expect(response.body).to include("Challenge alerts")
    end

    it "does not leak the VAPID meta tag to signed-out visitors" do
      get root_path

      expect(response.body).not_to include('name="vapid-public-key"')
    end

    it "shows the fighter's own match history on the homepage" do
      user = create(:user)
      sign_in_as(user)
      create(:fight, :resolved,
             challenger: user.fighter,
             opponent: create(:fighter, name: "Homepage Rival"),
             resolved_at: 1.hour.ago)

      get root_path

      expect(response.body).to include("Your match history")
      expect(response.body).to include("Homepage Rival")
    end

    it "seeds the inbox island with the fighter's incoming and outgoing challenges" do
      user = create(:user)
      sign_in_as(user)
      me = user.fighter
      challenger = create(:fighter, name: "Incoming Foe")
      Fight.create_challenge!(
        challenger: challenger, opponent: me,
        moves: (1..3).map { |r| { round: r, attack_height: 2, attack_style: 0, block_height: 2 } }
      )

      get root_path

      expect(response.body).to include("Incoming Foe")
      expect(response.body).to include('data-svelte-component="Inbox"')
    end
  end
end
