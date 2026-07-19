require "rails_helper"

RSpec.describe Bots::TickJob, type: :job do
  # A wide-open activity window and a near-certain login so presence is
  # deterministic; long sessions so an online bot won't randomly log off.
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
    it "logs an offline bot on during its active hours and announces it" do
      b = bot(last_seen_at: nil)

      expect { described_class.new.perform(now: in_window, rng: seeded) }
        .to have_broadcasted_to(DojoChannel::STREAM)
        .with(hash_including(event: "presence", online: true))

      expect(b.reload.last_seen_at).to be_within(2.seconds).of(in_window)
    end

    it "logs an online bot off once its window has passed and announces it" do
      b = bot(last_seen_at: out_of_window - 30.seconds)

      expect { described_class.new.perform(now: out_of_window, rng: seeded) }
        .to have_broadcasted_to(DojoChannel::STREAM)
        .with(hash_including(event: "presence", online: false))

      expect(b.reload.online?).to be(false)
    end

    it "leaves an offline bot offline outside its window" do
      b = bot(last_seen_at: nil)
      described_class.new.perform(now: out_of_window, rng: seeded)
      expect(b.reload.last_seen_at).to be_nil
    end
  end

  describe "responding to challenges" do
    it "resolves a pending challenge for an online bot" do
      human = create(:fighter, belt: 3, xp: 800)
      b = bot(belt: 3, xp: 800, last_seen_at: in_window)
      fight = challenge(challenger: human, opponent: b)
      fight.update_column(:created_at, in_window - 2.minutes)

      described_class.new.perform(now: in_window, rng: seeded)

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
      fight.update_column(:created_at, in_window - 2.minutes)

      expect { described_class.new.perform(now: in_window, rng: seeded) }
        .to change { b.reload.declines }.by(1)
      expect(fight.reload).to be_declined
    end

    it "does not respond for an offline bot" do
      human = create(:fighter, belt: 3)
      b = bot(belt: 3, last_seen_at: nil, persona_overrides: { "activity" => [ [ 22, 23 ] ] })
      fight = challenge(challenger: human, opponent: b)
      fight.update_column(:created_at, in_window - 2.minutes)

      described_class.new.perform(now: in_window, rng: seeded)
      expect(fight.reload).to be_pending
    end
  end

  describe "issuing challenges" do
    it "an aggressive online bot challenges an in-range fighter" do
      aggressor = bot(belt: 3, last_seen_at: in_window, persona_overrides: { "aggression" => 1.0 })
      target = bot(belt: 4, last_seen_at: in_window)

      expect { described_class.new.perform(now: in_window, rng: seeded) }
        .to change { Fight.pending.where(challenger: aggressor).count }.by(1)

      expect(Fight.pending.exists?(challenger: aggressor, opponent: target)).to be(true)
    end

    it "won't challenge a fighter more than two belts away" do
      aggressor = bot(belt: 3, last_seen_at: in_window, persona_overrides: { "aggression" => 1.0 })
      bot(belt: 8, last_seen_at: in_window) # far out of reach

      described_class.new.perform(now: in_window, rng: seeded)
      expect(Fight.pending.where(challenger: aggressor)).to be_empty
    end

    it "respects the pair cooldown and the single-outstanding rule" do
      aggressor = bot(belt: 3, last_seen_at: in_window, persona_overrides: { "aggression" => 1.0 })
      bot(belt: 3, last_seen_at: in_window)

      described_class.new.perform(now: in_window, rng: Random.new(1))
      first = Fight.pending.where(challenger: aggressor).count
      described_class.new.perform(now: in_window, rng: Random.new(2))

      # Already has an outstanding challenge out; a second tick can't stack another
      # on the same target, and the only in-range target is that one bot.
      expect(Fight.pending.where(challenger: aggressor).count).to eq(first)
    end

    it "caps pending challenges stacked on a single human" do
      human = create(:fighter, belt: 3, last_seen_at: in_window)
      other_a = create(:fighter, belt: 3)
      other_b = create(:fighter, belt: 3)
      challenge(challenger: other_a, opponent: human)
      challenge(challenger: other_b, opponent: human)

      aggressor = bot(belt: 3, last_seen_at: in_window, persona_overrides: { "aggression" => 1.0 })
      described_class.new.perform(now: in_window, rng: seeded)

      expect(Fight.pending.where(opponent: human).count).to eq(2)
      expect(Fight.pending.exists?(challenger: aggressor, opponent: human)).to be(false)
    end
  end
end
