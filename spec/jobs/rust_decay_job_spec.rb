require "rails_helper"

RSpec.describe RustDecayJob, type: :job do
  let(:now) { Time.current }
  let(:idle) { now - 20.days }
  let(:floor_xp) { Belt.threshold_for(RustDecayJob::FLOOR_BELT) } # Blue = 2500

  it "decays an idle high belt's XP by one percent" do
    brown = create(:fighter, belt: 7, xp: 6000, last_fought_at: idle)

    described_class.new.perform(now: now)

    expect(brown.reload.xp).to eq(5940) # floor(6000 * 0.99)
  end

  it "resettles the belt after decaying, demoting when XP falls far enough" do
    brown = create(:fighter, belt: 7, xp: 5650, last_fought_at: idle)

    described_class.new.perform(now: now)

    expect(brown.reload.belt).to eq(6) # 5650 → 5593, below brown's hysteresis band
  end

  it "never lets rust push XP below the blue floor, and stops the belt at blue" do
    purple = create(:fighter, belt: 6, xp: floor_xp + 10, last_fought_at: idle)

    described_class.new.perform(now: now)

    expect(purple.reload.xp).to eq(floor_xp)
    expect(purple.belt).to eq(RustDecayJob::FLOOR_BELT)
  end

  it "leaves blue and below untouched no matter how idle" do
    blue = create(:fighter, belt: 5, xp: 3000, last_fought_at: idle)

    expect { described_class.new.perform(now: now) }.not_to change { blue.reload.xp }
  end

  it "leaves recently-active fighters alone" do
    active = create(:fighter, belt: 8, xp: 9000, last_fought_at: now - 2.days)

    expect { described_class.new.perform(now: now) }.not_to change { active.reload.xp }
  end

  it "leaves a fighter who has never fought alone" do
    fresh = create(:fighter, belt: 8, xp: 9000, last_fought_at: nil)

    expect { described_class.new.perform(now: now) }.not_to change { fresh.reload.xp }
  end

  it "broadcasts a demotion to the dojo when a belt drops" do
    broadcasts = []
    allow(ActionCable.server).to receive(:broadcast) { |stream, message| broadcasts << [ stream, message ] }
    create(:fighter, belt: 7, xp: 5650, last_fought_at: idle)

    described_class.new.perform(now: now)

    dojo = broadcasts.select { |s, _| s == DojoChannel::STREAM }.map(&:last)
    demotion = dojo.find { |m| m[:event] == "belt_change" }
    expect(demotion).to be_present
    expect(demotion[:direction]).to eq("demotion")
  end
end
