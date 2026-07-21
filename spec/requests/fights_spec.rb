require "rails_helper"

RSpec.describe "Fights", type: :request do
  let(:challenger_user) { create(:user) }
  let(:challenger) { challenger_user.fighter.tap { |f| f.update!(belt: 3, xp: 800) } }
  let(:opponent_user) { create(:user) }
  let(:opponent) { opponent_user.fighter.tap { |f| f.update!(belt: 3, xp: 800) } }

  def resolved_fight
    fight = Fight.create_challenge!(
      challenger: challenger, opponent: opponent,
      moves: (1..3).map { |r| { round: r, attack_height: 3, attack_style: 0, block_height: 1 } }
    )
    fight.respond!(
      moves: (1..3).map { |r| { round: r, attack_height: 1, attack_style: 0, block_height: 2 } },
      rng: Random.new(1)
    )
    fight
  end

  def pending_fight
    Fight.create_challenge!(
      challenger: challenger, opponent: opponent,
      moves: (1..3).map { |r| { round: r, attack_height: 2, attack_style: 0, block_height: 2 } }
    )
  end

  describe "GET /fights/:id" do
    it "shows a resolved fight to any verified fighter (spectator/scout)" do
      fight = resolved_fight
      sign_in_as(create(:user))

      get fight_path(fight)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-svelte-component="FightPlayback"')
    end

    it "requires a verified fighter" do
      fight = resolved_fight
      get fight_path(fight)
      expect(response).to redirect_to(login_path)
    end

    it "hides a still-pending fight from non-participants" do
      challenger; opponent
      fight = pending_fight
      sign_in_as(create(:user))

      get fight_path(fight)
      expect(response).to redirect_to(root_path)
    end

    it "steps through the reveal only on a participant's FIRST view of their own fight" do
      fight = resolved_fight
      sign_in_as(challenger_user)

      get fight_path(fight)
      expect(response.body).to include("&quot;reveal&quot;:true")

      get fight_path(fight)
      expect(response.body).to include("&quot;reveal&quot;:false")
    end

    it "never hides results from spectators" do
      fight = resolved_fight
      sign_in_as(create(:user))

      get fight_path(fight)

      expect(response.body).to include("&quot;reveal&quot;:false")
      expect(fight.reload.challenger_seen_at).to be_nil
    end

    it "shows a participant a minimal pending state without move data" do
      opponent
      fight = pending_fight
      sign_in_as(challenger_user)

      get fight_path(fight)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('data-svelte-component="FightPlayback"')
      expect(response.body).not_to include("attack_height")
    end
  end
end
