require "rails_helper"

# ActJob is the actor: it carries out one bot's planned intent at its jittered
# second, RE-EVALUATING against current state (the plan may be up to a minute old).
RSpec.describe Bots::ActJob, type: :job do
  def persona(overrides = {})
    {
      "activity" => [ [ 10, 12 ] ],
      "session_chance" => 1.0,
      "session_minutes" => [ 100_000, 100_000 ],
      "aggression" => 0.0,
      "decline_style" => "grudging",
      "response_delay_minutes" => [ 0, 0 ]
    }.merge(overrides)
  end

  def bot(belt: 3, persona_overrides: {}, **attrs)
    create(:fighter, :bot, belt: belt,
           strategy: { "type" => "biased", "persona" => persona(persona_overrides) }, **attrs)
  end

  let(:in_window) { Time.utc(2025, 1, 6, 11) }
  let(:out_of_window) { Time.utc(2025, 1, 6, 20) }
  let(:seeded) { Random.new(1) }

  def challenge(challenger:, opponent:)
    Fight.create_challenge!(
      challenger: challenger, opponent: opponent,
      moves: (1..3).map { |r| { round: r, attack_height: 2, attack_style: 0, block_height: 2 } }
    )
  end

  describe "presence" do
    it "logs an offline bot on and announces it" do
      b = bot(last_seen_at: nil)

      expect { described_class.new.perform(b.id, presence: "login", now: in_window, rng: seeded) }
        .to have_broadcasted_to(DojoChannel::STREAM)
        .with(hash_including(event: "presence", online: true))

      expect(b.reload.last_seen_at).to be_within(2.seconds).of(in_window)
    end

    it "logs an online bot off and announces it" do
      b = bot(last_seen_at: out_of_window - 30.seconds)

      expect { described_class.new.perform(b.id, presence: "logout", now: out_of_window, rng: seeded) }
        .to have_broadcasted_to(DojoChannel::STREAM)
        .with(hash_including(event: "presence", online: false))

      expect(b.reload.online?).to be(false)
    end

    it "does not re-announce a login for a bot already online" do
      b = bot(last_seen_at: in_window - 10.seconds)

      expect { described_class.new.perform(b.id, presence: "login", now: in_window, rng: seeded) }
        .not_to have_broadcasted_to(DojoChannel::STREAM)
    end
  end

  describe "responding" do
    it "resolves a pending challenge end to end" do
      human = create(:fighter, belt: 3, xp: 800)
      b = bot(belt: 3, xp: 800, last_seen_at: in_window)
      fight = challenge(challenger: human, opponent: b)

      described_class.new.perform(b.id, respond_fight_ids: [ fight.id ], now: in_window, rng: seeded)

      expect(fight.reload).to be_resolved
      expect(fight.fight_rounds.count).to eq(3)
    end

    it "declines a farmed challenge per a proud temperament" do
      human = create(:fighter, belt: 3)
      b = bot(belt: 3, last_seen_at: in_window, persona_overrides: { "decline_style" => "proud" })

      Fight::FARM_LIMIT.times do
        f = challenge(challenger: human, opponent: b)
        f.update_columns(status: Fight.statuses[:resolved], created_at: 1.hour.ago)
      end
      fight = challenge(challenger: human, opponent: b)

      expect { described_class.new.perform(b.id, respond_fight_ids: [ fight.id ], now: in_window, rng: seeded) }
        .to change { b.reload.declines }.by(1)
      expect(fight.reload).to be_declined
    end

    it "skips a fight that resolved between plan and act (precondition re-check)" do
      human = create(:fighter, belt: 3, xp: 800)
      b = bot(belt: 3, xp: 800, last_seen_at: in_window)
      fight = challenge(challenger: human, opponent: b)
      # Simulate the fight settling in the window between planning and acting.
      fight.update_column(:status, Fight.statuses[:resolved])

      expect { described_class.new.perform(b.id, respond_fight_ids: [ fight.id ], now: in_window, rng: seeded) }
        .not_to change { fight.fight_rounds.count }
    end
  end

  describe "issuing a challenge" do
    it "challenges a live in-range fighter" do
      aggressor = bot(belt: 3, last_seen_at: in_window)
      target = bot(belt: 4, last_seen_at: in_window)

      expect { described_class.new.perform(aggressor.id, challenge: true, now: in_window, rng: seeded) }
        .to change { Fight.pending.where(challenger: aggressor).count }.by(1)

      expect(Fight.pending.exists?(challenger: aggressor, opponent: target)).to be(true)
    end

    it "won't challenge a fighter more than two belts away" do
      aggressor = bot(belt: 3, last_seen_at: in_window)
      bot(belt: 8, last_seen_at: in_window)

      described_class.new.perform(aggressor.id, challenge: true, now: in_window, rng: seeded)
      expect(Fight.pending.where(challenger: aggressor)).to be_empty
    end

    it "caps pending challenges stacked on a single human" do
      human = create(:fighter, belt: 3, last_seen_at: in_window)
      other_a = create(:fighter, belt: 3)
      other_b = create(:fighter, belt: 3)
      challenge(challenger: other_a, opponent: human)
      challenge(challenger: other_b, opponent: human)

      aggressor = bot(belt: 3, last_seen_at: in_window)
      described_class.new.perform(aggressor.id, challenge: true, now: in_window, rng: seeded)

      expect(Fight.pending.where(opponent: human).count).to eq(2)
      expect(Fight.pending.exists?(challenger: aggressor, opponent: human)).to be(false)
    end

    it "respects the pair cooldown after a recent fight" do
      # The cooldown gate reads wall-clock (Fight::CHALLENGE_COOLDOWN.ago), so this
      # case runs on real Time.current rather than the injected sim clock.
      now = Time.current
      aggressor = bot(belt: 3, last_seen_at: now)
      rival = bot(belt: 3, last_seen_at: now)
      f = challenge(challenger: aggressor, opponent: rival)
      f.update_columns(status: Fight.statuses[:resolved], created_at: now - 1.minute)

      described_class.new.perform(aggressor.id, challenge: true, now: now, rng: seeded)
      expect(Fight.pending.where(challenger: aggressor)).to be_empty
    end
  end

  it "no-ops cleanly on a missing bot id" do
    expect { described_class.new.perform(-1, presence: "login") }.not_to raise_error
  end
end
