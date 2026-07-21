require "rails_helper"

RSpec.describe "Challenges", type: :request do
  let(:user) { create(:user) }
  let(:me) { user.fighter }
  let(:opponent_user) { create(:user) }
  let(:opponent) { opponent_user.fighter.tap { |f| f.update!(belt: 3, xp: 800) } }

  def moves_json(attack: 2, block: 2, style: 0)
    (1..3).map { |r| { round: r, attack_height: attack, attack_style: style, block_height: block } }.to_json
  end

  before { sign_in_as(user) }

  describe "GET /challenges/new" do
    it "shows the commit grid against the chosen opponent" do
      get new_challenge_path(opponent: opponent.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-svelte-component="MoveCommitter"')
      expect(response.body).to include(opponent.name)
    end

    it "refuses to build a self-challenge" do
      get new_challenge_path(opponent: me.id)
      expect(response).to redirect_to(fighters_path)
    end

    it "surfaces a scouting panel of the opponent's recent resolved fights" do
      prey = create(:fighter, name: "Old Foe", belt: 2)
      create(:fight, :resolved, challenger: opponent, opponent: prey, resolved_at: 1.hour.ago)

      get new_challenge_path(opponent: opponent.id)

      expect(response.body).to include("Scouting")
      expect(response.body).to include("Old Foe")
      expect(response.body).to include("Full history")
    end
  end

  describe "POST /challenges" do
    it "seals a challenge and redirects to the opponent's profile" do
      expect {
        post challenges_path, params: { opponent: opponent.id, moves: moves_json }
      }.to change(Fight, :count).by(1)

      fight = Fight.last
      expect(fight.challenger).to eq(me)
      expect(fight.opponent).to eq(opponent)
      expect(fight.fight_moves.where(fighter: me).count).to eq(3)
      expect(response).to redirect_to(fighter_path(opponent))
      expect(flash[:notice]).to be_present
    end

    it "stores an optional trimmed challenge message the opponent will see" do
      post challenges_path, params: { opponent: opponent.id, moves: moves_json, message: "  Revenge incoming!  " }

      fight = Fight.last
      expect(fight.challenge_message).to eq("Revenge incoming!")

      sign_in_as(opponent_user)
      get challenge_path(fight)
      expect(response.body).to include("Revenge incoming!")

      get challenge_path(fight), headers: { "Accept" => "application/json" }
      expect(response.parsed_body["message"]).to eq("Revenge incoming!")
    end

    it "rejects a message over the length cap" do
      expect {
        post challenges_path, params: { opponent: opponent.id, moves: moves_json, message: "x" * 281 }
      }.not_to change(Fight, :count)
      expect(flash[:alert]).to be_present
    end

    it "stores nil when the message is blank" do
      post challenges_path, params: { opponent: opponent.id, moves: moves_json, message: "   " }

      expect(Fight.last.challenge_message).to be_nil
    end

    it "rejects a self-challenge with a flash" do
      expect {
        post challenges_path, params: { opponent: me.id, moves: moves_json }
      }.not_to change(Fight, :count)
      expect(flash[:alert]).to be_present
    end

    it "rejects a second challenge inside the cooldown window" do
      # A recently resolved fight between the pair leaves nothing pending, so the
      # rejection is the time-based cooldown rather than the single-outstanding rule.
      create(:fight, :resolved, challenger: me, opponent: opponent, created_at: 1.minute.ago)

      expect {
        post challenges_path, params: { opponent: opponent.id, moves: moves_json }
      }.not_to change(Fight, :count)
      expect(flash[:alert]).to match(/too recently|cooldown/i)
    end

    it "rejects a second pending challenge in the same direction" do
      post challenges_path, params: { opponent: opponent.id, moves: moves_json }

      expect {
        post challenges_path, params: { opponent: opponent.id, moves: moves_json }
      }.not_to change(Fight, :count)
      expect(flash[:alert]).to match(/already have a challenge/i)
    end

    it "allows a pending challenge in the opposite direction" do
      # An outstanding challenge FROM the opponent, aged past the cooldown, must not
      # block a counter-challenge back at them.
      incoming = Fight.create_challenge!(
        challenger: opponent, opponent: me,
        moves: (1..3).map { |r| { round: r, attack_height: 2, attack_style: 0, block_height: 2 } }
      )
      incoming.update_column(:created_at, (Fight::CHALLENGE_COOLDOWN + 1.minute).ago)

      expect {
        post challenges_path, params: { opponent: opponent.id, moves: moves_json }
      }.to change(Fight, :count).by(1)
    end
  end

  describe "GET /challenges/new.json (challenge modal payload)" do
    it "returns the opponent summary and scouting without any declines" do
      opponent.update!(declines: 7)
      prey = create(:fighter, name: "Scout Bait", belt: 2)
      create(:fight, :resolved, challenger: opponent, opponent: prey, resolved_at: 1.hour.ago)

      get new_challenge_path(opponent: opponent.id, format: :json)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["mode"]).to eq("challenge")
      expect(body.dig("opponent", "name")).to eq(opponent.name)
      expect(body["scouting"].first["opponent_name"]).to include("Scout Bait")
      expect(response.body).not_to include("declines")
      expect(response.body).not_to include("\"7\"")
    end

    it "carries the opponent's resolved moves as key-free tuples for the pattern read" do
      prey = create(:fighter, name: "Pattern Prey", belt: 2)
      fight = create(:fight, :resolved, challenger: opponent, opponent: prey, resolved_at: 1.hour.ago)
      (1..3).each do |round|
        fight.fight_moves.create!(fighter: opponent, round: round, attack_height: 3, attack_style: 1, block_height: 1)
      end

      get new_challenge_path(opponent: opponent.id, format: :json)

      moves = JSON.parse(response.body)["scouting"].first["moves"]
      expect(moves).to eq([ [ 3, 1, 1 ], [ 3, 1, 1 ], [ 3, 1, 1 ] ])
      expect(response.body).not_to include("attack_height")
      expect(response.body).not_to include("block_height")
    end
  end

  describe "GET /challenges/:id.json (respond modal payload) sealed-moves secrecy" do
    let!(:fight) do
      Fight.create_challenge!(
        challenger: me, opponent: opponent,
        moves: (1..3).map { |r| { round: r, attack_height: 3, attack_style: 1, block_height: 1 } }
      )
    end

    it "gives the opponent the challenger's scouting but zero sealed move data" do
      opponent; sign_in_as(opponent_user)

      get challenge_path(fight, format: :json)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["mode"]).to eq("respond")
      expect(body["fight_id"]).to eq(fight.id)
      expect(response.body).not_to include("attack_height")
      expect(response.body).not_to include("block_height")
    end

    it "forbids anyone but the opponent from fetching it" do
      sign_in_as(create(:user))
      get challenge_path(fight, format: :json)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /challenges/:id (respond page) sealed-moves secrecy" do
    let!(:fight) do
      # Distinctive committed moves: challenger attacks high(3) with punches(1),
      # blocks low(1) every round. If any of that reaches the respond page, the
      # opponent could cheat.
      Fight.create_challenge!(
        challenger: me, opponent: opponent,
        moves: (1..3).map { |r| { round: r, attack_height: 3, attack_style: 1, block_height: 1 } }
      )
    end

    it "shows the opponent the respond page without any challenger move data" do
      opponent; sign_in_as(opponent_user)
      # A prior resolved fight for the challenger — the scouting panel surfaces it,
      # which is public history and must not be confused with the sealed challenge.
      create(:fight, :resolved, challenger: me, opponent: create(:fighter, name: "Past Rival"),
             resolved_at: 2.hours.ago)
      get challenge_path(fight)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-svelte-component="MoveCommitter"')
      # The scouting surface is present (the challenger's public history)...
      expect(response.body).to include("Scouting")
      expect(response.body).to include("Past Rival")
      # ...but no serialized move data for THIS sealed challenge leaks: the payload
      # keys never appear, nor does the FightPlayback island (the only thing that
      # carries movesets).
      expect(response.body).not_to include("attack_height")
      expect(response.body).not_to include("block_height")
      expect(response.body).not_to include("FightPlayback")
      moves_leak = fight.fight_moves.where(fighter: me).map { |m|
        { attack_height: m.attack_height, attack_style: m.attack_style, block_height: m.block_height }.to_json
      }
      moves_leak.each { |json| expect(response.body).not_to include(json) }
    end

    it "shows the challenger a read-only waiting state" do
      get challenge_path(fight)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Awaiting")
      expect(response.body).not_to include("Accept &amp; fight")
    end

    it "turns strangers away from a pending fight" do
      sign_in_as(create(:user))
      get challenge_path(fight)
      expect(response).to redirect_to(root_path)
    end
  end

  describe "POST /challenges/:id/accept" do
    let!(:fight) do
      Fight.create_challenge!(
        challenger: me, opponent: opponent,
        moves: (1..3).map { |r| { round: r, attack_height: 3, attack_style: 0, block_height: 1 } }
      )
    end

    it "lets the opponent accept, resolving the fight" do
      opponent; sign_in_as(opponent_user)

      post accept_challenge_path(fight), params: { moves: moves_json(attack: 1, block: 2) }

      expect(fight.reload).to be_resolved
      expect(response).to redirect_to(fight_path(fight))
    end

    it "forbids a non-opponent from accepting" do
      sign_in_as(create(:user))
      post accept_challenge_path(fight), params: { moves: moves_json }

      expect(fight.reload).to be_pending
      expect(response).to redirect_to(root_path)
    end
  end

  describe "POST /challenges/:id/decline" do
    let!(:fight) do
      Fight.create_challenge!(
        challenger: me, opponent: opponent,
        moves: (1..3).map { |r| { round: r, attack_height: 2, attack_style: 0, block_height: 2 } }
      )
    end

    it "lets the opponent decline" do
      opponent; sign_in_as(opponent_user)

      expect {
        post decline_challenge_path(fight)
      }.to change { opponent.reload.declines }.by(1)
      expect(fight.reload).to be_declined
    end

    it "forbids a non-opponent from declining" do
      sign_in_as(create(:user))
      post decline_challenge_path(fight)
      expect(fight.reload).to be_pending
    end
  end
end
