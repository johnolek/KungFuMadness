require "rails_helper"

RSpec.describe Fight, type: :model do
  it { is_expected.to belong_to(:challenger).class_name("Fighter") }
  it { is_expected.to belong_to(:opponent).class_name("Fighter") }
  it { is_expected.to belong_to(:winner).class_name("Fighter").optional }
  it { is_expected.to have_many(:fight_rounds).dependent(:destroy) }

  it "defines the challenge-lifecycle statuses" do
    expect(Fight.statuses.keys).to eq(%w[pending resolved declined expired])
  end

  it "builds a valid pending fight from the factory" do
    expect(build(:fight)).to be_valid
  end

  it "rejects a fighter challenging themselves" do
    fighter = create(:fighter)
    fight = build(:fight, challenger: fighter, opponent: fighter)
    expect(fight).not_to be_valid
    expect(fight.errors[:opponent]).to be_present
  end

  describe "scopes" do
    it "finds fights involving a fighter on either side" do
      fighter = create(:fighter)
      as_challenger = create(:fight, challenger: fighter)
      as_opponent = create(:fight, opponent: fighter)
      other = create(:fight)

      involving = Fight.for_fighter(fighter)
      expect(involving).to include(as_challenger, as_opponent)
      expect(involving).not_to include(other)
    end

    it "finds pending fights past their expiry" do
      stale = create(:fight, status: :pending, expires_at: 1.hour.ago)
      fresh = create(:fight, status: :pending, expires_at: 1.hour.from_now)

      expect(Fight.pending.past_expiry).to include(stale)
      expect(Fight.pending.past_expiry).not_to include(fresh)
    end

    it "finds fights between a pair regardless of who challenged" do
      a = create(:fighter)
      b = create(:fighter)
      forward = create(:fight, challenger: a, opponent: b)
      backward = create(:fight, challenger: b, opponent: a)
      unrelated = create(:fight, challenger: a)

      expect(Fight.between(a, b)).to contain_exactly(forward, backward)
      expect(Fight.between(a, b)).not_to include(unrelated)
    end
  end

  # Moves where the challenger blocks every opponent attack and lands every one of
  # their own — a guaranteed challenger KO regardless of the dice, so lifecycle
  # assertions don't depend on the RNG seed.
  def decisive_challenger_moves
    (1..3).map { |r| { round: r, attack_height: 3, attack_style: 0, block_height: 1 } }
  end

  def decisive_opponent_moves
    (1..3).map { |r| { round: r, attack_height: 1, attack_style: 1, block_height: 2 } }
  end

  describe ".create_challenge!" do
    let(:challenger) { create(:fighter, belt: 3, xp: 800) }
    let(:opponent) { create(:fighter, belt: 5, xp: 2500) }

    it "snapshots both fighters' belt and xp at creation" do
      fight = Fight.create_challenge!(challenger: challenger, opponent: opponent, moves: decisive_challenger_moves)

      expect(fight).to be_pending
      expect(fight.challenger_belt).to eq(3)
      expect(fight.challenger_xp).to eq(800)
      expect(fight.opponent_belt).to eq(5)
      expect(fight.opponent_xp).to eq(2500)
      expect(fight.expires_at).to be_within(1.minute).of(Fight::CHALLENGE_TTL.from_now)
    end

    it "is fought at the snapshot belt even if a fighter belts up before responding" do
      fight = Fight.create_challenge!(challenger: challenger, opponent: opponent, moves: decisive_challenger_moves)
      opponent.update!(belt: 9, xp: 12_000)

      expect(fight.opponent_belt).to eq(5)
    end

    it "writes exactly the challenger's three move rows" do
      fight = Fight.create_challenge!(challenger: challenger, opponent: opponent, moves: decisive_challenger_moves)

      expect(fight.fight_moves.where(fighter: challenger).count).to eq(3)
      expect(fight.fight_moves.where(fighter: opponent).count).to eq(0)
    end

    it "rejects a self-challenge" do
      expect {
        Fight.create_challenge!(challenger: challenger, opponent: challenger, moves: decisive_challenger_moves)
      }.to raise_error(Fight::ChallengeError)
    end

    it "rejects a bot challenging a human who turned bot challenges off" do
      user = create(:user)
      user.update!(allow_bot_challenges: false)
      bot = create(:fighter, :bot, belt: 1)

      expect {
        Fight.create_challenge!(challenger: bot, opponent: user.fighter, moves: decisive_challenger_moves)
      }.to raise_error(Fight::ChallengeError, /doesn't accept challenges from bots/)
    end

    it "still lets a human challenge someone who turned bot challenges off" do
      user = create(:user)
      user.update!(allow_bot_challenges: false)

      fight = Fight.create_challenge!(challenger: challenger, opponent: user.fighter, moves: decisive_challenger_moves)
      expect(fight).to be_pending
    end

    it "rejects a challenge inside the cooldown window with the pair" do
      Fight.create_challenge!(challenger: challenger, opponent: opponent, moves: decisive_challenger_moves)

      expect {
        Fight.create_challenge!(challenger: challenger, opponent: opponent, moves: decisive_challenger_moves)
      }.to raise_error(Fight::ChallengeError)
    end

    it "counts the cooldown in either direction" do
      Fight.create_challenge!(challenger: challenger, opponent: opponent, moves: decisive_challenger_moves)

      expect {
        Fight.create_challenge!(challenger: opponent, opponent: challenger, moves: decisive_challenger_moves)
      }.to raise_error(Fight::ChallengeError)
    end

    it "allows a fresh challenge once the cooldown has passed and no pending one stands" do
      old = Fight.create_challenge!(challenger: challenger, opponent: opponent, moves: decisive_challenger_moves)
      old.update!(status: :declined)
      old.update_column(:created_at, (Fight::CHALLENGE_COOLDOWN + 1.minute).ago)

      expect {
        Fight.create_challenge!(challenger: challenger, opponent: opponent, moves: decisive_challenger_moves)
      }.not_to raise_error
    end

    it "rejects a second pending challenge in the same direction (single outstanding)" do
      Fight.create_challenge!(challenger: challenger, opponent: opponent, moves: decisive_challenger_moves)

      expect {
        Fight.create_challenge!(challenger: challenger, opponent: opponent, moves: decisive_challenger_moves)
      }.to raise_error(Fight::ChallengeError, /already have a challenge/i)
    end

    it "allows a pending challenge in the opposite direction (mutual sealed challenges)" do
      old = Fight.create_challenge!(challenger: challenger, opponent: opponent, moves: decisive_challenger_moves)
      # Push it out of the cooldown window so only the direction rule is under test.
      old.update_column(:created_at, (Fight::CHALLENGE_COOLDOWN + 1.minute).ago)

      expect {
        Fight.create_challenge!(challenger: opponent, opponent: challenger, moves: decisive_challenger_moves)
      }.not_to raise_error
    end

    it "leaves no partial challenge if move writing fails" do
      bad_moves = [ { round: 1, attack_height: 99, attack_style: 0, block_height: 1 } ]

      expect {
        expect {
          Fight.create_challenge!(challenger: challenger, opponent: opponent, moves: bad_moves)
        }.to raise_error(ActiveRecord::RecordInvalid)
      }.not_to change(Fight, :count)
    end
  end

  describe "spoiler shield" do
    let(:user) { create(:user) }
    let(:me) { user.fighter }
    let(:rival) { create(:fighter, name: "Rival") }
    let(:fight) { create(:fight, :resolved, challenger: me, opponent: rival, winner: rival) }

    it "flags an unwatched resolved fight for a participant with spoilers hidden" do
      expect(fight.spoiler_for?(me)).to be(true)
    end

    it "does not flag once the participant has watched" do
      fight.update!(challenger_seen_at: Time.current)
      expect(fight.spoiler_for?(me)).to be(false)
    end

    it "does not flag when the user shows spoilers" do
      user.update!(hide_fight_spoilers: false)
      expect(fight.spoiler_for?(me)).to be(false)
    end

    it "never flags spectators, userless fighters, or nil viewers" do
      expect(fight.spoiler_for?(create(:fighter))).to be(false)
      expect(fight.spoiler_for?(rival)).to be(false)
      expect(fight.spoiler_for?(nil)).to be(false)
    end

    it "masks the history row: no result, KO, moves, or XP" do
      row = fight.history_row_payload(viewer: me, mask_for: me)

      expect(row[:masked]).to be(true)
      expect(row.values_at(:result, :ko, :xp_delta)).to all(be_nil)
      expect(row[:moves]).to eq([])
      expect(row[:opponent_name]).to eq("Rival")
    end

    it "leaves the history row intact for other viewers" do
      row = fight.history_row_payload(viewer: me, mask_for: nil)

      expect(row[:masked]).to be_nil
      expect(row[:result]).to eq("loss")
    end

    it "masks the ticker payload for the unwatched participant only" do
      masked = fight.ticker_payload(mask_for: me)
      open = fight.ticker_payload

      expect(masked[:masked]).to be(true)
      expect(masked.values_at(:winner_side, :ko, :draw)).to all(be_nil)
      expect(masked[:challenger][:moves]).to eq([])
      expect(open[:winner_side]).to eq("opponent")
    end
  end

  describe "#respond!" do
    let(:challenger) { create(:fighter, belt: 3, xp: 800) }
    let(:opponent) { create(:fighter, belt: 3, xp: 800) }
    let(:fight) do
      Fight.create_challenge!(challenger: challenger, opponent: opponent, moves: decisive_challenger_moves)
    end

    it "resolves the fight, writing rounds and the outcome" do
      expect(fight.respond!(moves: decisive_opponent_moves, rng: Random.new(1))).to be(true)
      fight.reload

      expect(fight).to be_resolved
      expect(fight.winner).to eq(challenger)
      expect(fight.ko).to be(true)
      expect(fight.fight_rounds.count).to eq(3)
      expect(fight.resolved_at).to be_present
    end

    it "applies snapshot-based XP, counters, and last_fought_at to both fighters" do
      fight.respond!(moves: decisive_opponent_moves, rng: Random.new(1))

      expect(fight.challenger_xp_delta).to eq(Xp::Rules::WIN_BASE)
      expect(fight.opponent_xp_delta).to eq(-Xp::Rules::LOSS_BASE)

      expect(challenger.reload.xp).to eq(800 + Xp::Rules::WIN_BASE)
      expect(challenger.wins).to eq(1)
      expect(challenger.losses).to eq(0)
      expect(challenger.last_fought_at).to be_present

      expect(opponent.reload.xp).to eq(800 - Xp::Rules::LOSS_BASE)
      expect(opponent.losses).to eq(1)
      expect(opponent.wins).to eq(0)
    end

    it "writes the opponent's committed moves" do
      fight.respond!(moves: decisive_opponent_moves, rng: Random.new(1))

      expect(fight.fight_moves.where(fighter: opponent).count).to eq(3)
    end

    it "settles a belt promotion off the applied XP" do
      near_promo = create(:fighter, belt: 3, xp: 1490) # yellow→green threshold is 1500
      low = create(:fighter, belt: 3, xp: 1490)
      f = Fight.create_challenge!(challenger: near_promo, opponent: low, moves: decisive_challenger_moves)

      f.respond!(moves: decisive_opponent_moves, rng: Random.new(1))

      expect(near_promo.reload.xp).to eq(1590)
      expect(near_promo.belt).to eq(4)
    end

    it "is a no-op on a double submit (row lock + status guard)" do
      fight.respond!(moves: decisive_opponent_moves, rng: Random.new(1))
      xp_after_first = opponent.reload.xp

      expect(fight.respond!(moves: decisive_opponent_moves, rng: Random.new(1))).to be(false)
      expect(opponent.reload.xp).to eq(xp_after_first)
      expect(fight.reload.fight_rounds.count).to eq(3)
    end

    it "lazily expires and refuses a fight touched past its deadline" do
      fight.update_column(:expires_at, 1.hour.ago)

      expect(fight.respond!(moves: decisive_opponent_moves)).to be(false)
      expect(fight.reload).to be_expired
      expect(fight.fight_rounds).to be_empty
    end
  end

  describe "#decline!" do
    let(:challenger) { create(:fighter) }
    let(:opponent) { create(:fighter) }
    let(:fight) do
      Fight.create_challenge!(challenger: challenger, opponent: opponent,
                              moves: (1..3).map { |r| { round: r, attack_height: 2, attack_style: 0, block_height: 2 } })
    end

    it "declines and counts the decline on the opponent" do
      expect { expect(fight.decline!).to be(true) }.to change { opponent.reload.declines }.by(1)
      expect(fight.reload).to be_declined
    end

    it "is a no-op on a second decline" do
      fight.decline!
      expect(fight.decline!).to be(false)
      expect(opponent.reload.declines).to eq(1)
    end

    it "lazily expires and refuses a decline past the deadline" do
      fight.update_column(:expires_at, 1.hour.ago)
      expect(fight.decline!).to be(false)
      expect(fight.reload).to be_expired
    end
  end

  describe "sealed payloads" do
    let(:fight) do
      Fight.create_challenge!(challenger: create(:fighter), opponent: create(:fighter),
                              moves: (1..3).map { |r| { round: r, attack_height: 2, attack_style: 0, block_height: 2 } })
    end

    it "exposes no move data before resolution" do
      expect(fight.playback_payload).to be_nil
      expect(fight.inbox_payload[:challenger]).not_to have_key(:moves)
      expect(fight.inbox_payload[:opponent]).not_to have_key(:moves)
    end

    it "exposes both movesets and rounds once resolved" do
      fight.respond!(moves: (1..3).map { |r| { round: r, attack_height: 1, attack_style: 0, block_height: 3 } }, rng: Random.new(1))
      payload = fight.reload.playback_payload

      expect(payload[:challenger][:moves].size).to eq(3)
      expect(payload[:opponent][:moves].size).to eq(3)
      expect(payload[:rounds].size).to eq(3)
    end
  end

  # The full risk loop, exercised through real Fight#resolve! rather than the Belt
  # unit tests: a loss actually demotes, a hard loss drops a white belt into Tofu,
  # and a Tofu win escapes straight back to White.
  describe "progression risk (integration through resolve!)" do
    def winning_challenger_moves
      (1..3).map { |r| { round: r, attack_height: 3, attack_style: 0, block_height: 1 } }
    end

    def losing_opponent_moves
      (1..3).map { |r| { round: r, attack_height: 1, attack_style: 1, block_height: 2 } }
    end

    it "demotes the loser a belt when the loss drops XP past the hysteresis band" do
      winner = create(:fighter, belt: 1, xp: 0)
      # Yellow at exactly its threshold; a −90 loss to a white belt drops it below
      # the demotion band (300 − 20%·300 = 240) and back to White.
      loser = create(:fighter, belt: 2, xp: 300)
      fight = Fight.create_challenge!(challenger: winner, opponent: loser, moves: winning_challenger_moves)

      fight.respond!(moves: losing_opponent_moves, rng: Random.new(1))

      expect(loser.reload.xp).to eq(210)
      expect(loser.belt).to eq(1)
    end

    it "drops a white belt into Tofu on a loss that takes XP negative" do
      winner = create(:fighter, belt: 1, xp: 0)
      loser = create(:fighter, belt: 1, xp: 40) # −50 same-belt loss → −10
      fight = Fight.create_challenge!(challenger: winner, opponent: loser, moves: winning_challenger_moves)

      fight.respond!(moves: losing_opponent_moves, rng: Random.new(1))

      expect(loser.reload.xp).to eq(-10)
      expect(loser.belt).to eq(0)
      expect(loser).to be_tofu
    end

    it "escapes Tofu straight to White on the next win" do
      escapee = create(:fighter, belt: 0, xp: -10)
      foil = create(:fighter, belt: 1, xp: 0)
      # Escapee wins as the challenger (belt-0 snapshot): a +150 win lifts XP to ≥0.
      fight = Fight.create_challenge!(challenger: escapee, opponent: foil, moves: winning_challenger_moves)

      fight.respond!(moves: losing_opponent_moves, rng: Random.new(1))

      expect(escapee.reload.xp).to be >= 0
      expect(escapee.belt).to eq(1)
      expect(escapee).not_to be_tofu
    end
  end
end
