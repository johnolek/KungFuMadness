require "rails_helper"

# The living-world broadcasts fired off Fight's commit callbacks. Captured by
# stubbing ActionCable.server.broadcast (tracker's Item pattern), so the assertions
# read the exact stream + payload without a live cable adapter.
RSpec.describe "Fight broadcasting", type: :model do
  let(:challenger) { create(:fighter, belt: 3, xp: 800) }
  let(:opponent) { create(:fighter, belt: 3, xp: 800) }

  def moves(height = 2, style = 0, block = 2)
    (1..3).map { |r| { round: r, attack_height: height, attack_style: style, block_height: block } }
  end

  before do
    @broadcasts = []
    allow(ActionCable.server).to receive(:broadcast) do |stream, message|
      @broadcasts << [ stream, message ]
    end
  end

  def messages_for(stream)
    @broadcasts.select { |s, _| s == stream }.map(&:last)
  end

  describe "creating a challenge" do
    it "notifies the opponent's FighterChannel with challenge_received" do
      Fight.create_challenge!(challenger: challenger, opponent: opponent, moves: moves)

      message = messages_for(FighterChannel.broadcasting_for(opponent)).last
      expect(message).to be_present
      expect(message[:event]).to eq("challenge_received")
      expect(message.dig(:fight, :challenger, :name)).to eq(challenger.name)
    end

    it "carries no sealed challenger move data in the challenge_received payload" do
      Fight.create_challenge!(challenger: challenger, opponent: opponent,
                              moves: moves(3, 1, 1))

      message = messages_for(FighterChannel.broadcasting_for(opponent)).last
      expect(message.to_json).not_to include("attack_height")
      expect(message.dig(:fight, :challenger)).not_to have_key(:moves)
    end
  end

  describe "resolving a fight" do
    it "feeds the dojo ticker and tells the challenger it settled" do
      fight = Fight.create_challenge!(challenger: challenger, opponent: opponent, moves: moves)
      @broadcasts.clear

      fight.respond!(moves: moves(1, 0, 3), rng: Random.new(1))

      dojo = messages_for(DojoChannel::STREAM).last
      expect(dojo[:event]).to eq("fight_resolved")
      expect(dojo.dig(:fight, :id)).to eq(fight.id)

      to_challenger = messages_for(FighterChannel.broadcasting_for(challenger)).last
      expect(to_challenger[:event]).to eq("challenge_resolved")
      expect(to_challenger.dig(:fight, :id)).to eq(fight.id)
    end
  end

  describe "declining a challenge" do
    it "tells the challenger it was declined" do
      fight = Fight.create_challenge!(challenger: challenger, opponent: opponent, moves: moves)
      @broadcasts.clear

      fight.decline!

      message = messages_for(FighterChannel.broadcasting_for(challenger)).last
      expect(message[:event]).to eq("challenge_declined")
      expect(message.dig(:fight, :id)).to eq(fight.id)
    end
  end
end
