require "rails_helper"

# TickJob is a PLANNER: it decides intent and enqueues a Bots::ActJob per acting
# bot at a jittered second. It performs no presence/respond/challenge side effects
# itself — those are asserted against Bots::ActJob. Here we assert the plan: the
# right intents reach the right bots, waits land inside the minute, and idle bots
# get no job.
RSpec.describe Bots::TickJob, type: :job do
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

  # The test adapter's queue isn't auto-cleared under RSpec, so wipe it each example.
  before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  def act_jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j[:job] == Bots::ActJob }
  end

  describe "presence planning" do
    it "plans a login for an offline bot in its active hours" do
      b = bot(last_seen_at: nil)

      expect { described_class.new.perform(now: in_window, rng: seeded) }
        .to have_enqueued_job(Bots::ActJob)
        .with(b.id, presence: "login", respond_fight_ids: [], challenge: false)
    end

    it "plans a logout for an online bot once its window has passed" do
      b = bot(last_seen_at: out_of_window - 30.seconds)

      expect { described_class.new.perform(now: out_of_window, rng: seeded) }
        .to have_enqueued_job(Bots::ActJob)
        .with(b.id, presence: "logout", respond_fight_ids: [], challenge: false)
    end

    it "enqueues nothing for an offline bot outside its window" do
      bot(last_seen_at: nil, persona_overrides: { "activity" => [ [ 22, 23 ] ] })
      described_class.new.perform(now: in_window, rng: seeded)
      expect(act_jobs).to be_empty
    end
  end

  describe "jitter" do
    it "schedules every ActJob at a random second inside the minute" do
      5.times { bot(last_seen_at: nil) }

      # The wait rides real wall-clock (durable Solid Queue delay), not the injected
      # sim clock, so bound it against Time.current around the enqueue.
      t0 = Time.current
      described_class.new.perform(now: in_window, rng: seeded)
      ceiling = Time.current.to_f + 59

      expect(act_jobs).not_to be_empty
      act_jobs.each do |job|
        expect(job[:at]).to be_between(t0.to_f, ceiling).inclusive
      end
    end
  end

  describe "respond planning" do
    it "flags a ready pending challenge for an online bot to answer" do
      human = create(:fighter, belt: 3, xp: 800)
      b = bot(belt: 3, xp: 800, last_seen_at: in_window)
      fight = challenge(challenger: human, opponent: b)
      fight.update_column(:created_at, in_window - 2.minutes)

      expect { described_class.new.perform(now: in_window, rng: seeded) }
        .to have_enqueued_job(Bots::ActJob)
        .with(b.id, presence: nil, respond_fight_ids: [ fight.id ], challenge: false)
    end

    it "does not flag challenges for an offline bot" do
      human = create(:fighter, belt: 3)
      b = bot(belt: 3, last_seen_at: nil, persona_overrides: { "activity" => [ [ 22, 23 ] ] })
      fight = challenge(challenger: human, opponent: b)
      fight.update_column(:created_at, in_window - 2.minutes)

      described_class.new.perform(now: in_window, rng: seeded)
      expect(act_jobs).to be_empty
    end
  end

  describe "challenge planning" do
    it "flags an aggressive online bot to go looking for a fight" do
      aggressor = bot(belt: 3, last_seen_at: in_window, persona_overrides: { "aggression" => 1.0 })

      expect { described_class.new.perform(now: in_window, rng: seeded) }
        .to have_enqueued_job(Bots::ActJob)
        .with(aggressor.id, presence: nil, respond_fight_ids: [], challenge: true)
    end
  end

  describe "inline mode (bots:tick rake)" do
    it "acts immediately in-process without enqueuing" do
      human = create(:fighter, belt: 3, xp: 800)
      b = bot(belt: 3, xp: 800, last_seen_at: in_window)
      fight = challenge(challenger: human, opponent: b)
      fight.update_column(:created_at, in_window - 2.minutes)

      described_class.new.perform(now: in_window, rng: seeded, inline: true)

      expect(act_jobs).to be_empty
      expect(fight.reload).to be_resolved
    end
  end
end
