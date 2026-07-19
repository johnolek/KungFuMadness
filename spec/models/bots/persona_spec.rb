require "rails_helper"

RSpec.describe Bots::Persona do
  # A deterministic RNG whose successive rand outputs are the queued values.
  def rng_returning(*values)
    queue = values.dup
    rng = instance_double(Random)
    allow(rng).to receive(:rand) { queue.shift }
    rng
  end

  describe "#active_now?" do
    it "is true inside an activity window and false outside it" do
      persona = described_class.new("activity" => [ [ 13, 17 ] ])
      expect(persona.active_now?(Time.utc(2025, 1, 1, 14))).to be(true)
      expect(persona.active_now?(Time.utc(2025, 1, 1, 18))).to be(false)
    end

    it "handles a window that wraps past midnight" do
      persona = described_class.new("activity" => [ [ 22, 2 ] ])
      expect(persona.active_now?(Time.utc(2025, 1, 1, 23))).to be(true)
      expect(persona.active_now?(Time.utc(2025, 1, 1, 1))).to be(true)
      expect(persona.active_now?(Time.utc(2025, 1, 1, 12))).to be(false)
    end

    it "reads the hour in UTC regardless of the passed zone" do
      persona = described_class.new("activity" => [ [ 13, 17 ] ])
      expect(persona.active_now?(Time.utc(2025, 1, 1, 14).in_time_zone("Tokyo"))).to be(true)
    end
  end

  describe "session decisions" do
    it "logs in when the roll beats session_chance" do
      persona = described_class.new("session_chance" => 0.3)
      expect(persona.wants_to_login?(rng_returning(0.2))).to be(true)
      expect(persona.wants_to_login?(rng_returning(0.5))).to be(false)
    end

    it "sets logout odds so sessions last about session_minutes on average" do
      persona = described_class.new("session_minutes" => [ 20, 40 ]) # mean 30 → 1/30 logoff
      expect(persona.avg_session_minutes).to eq(30.0)
      expect(persona.wants_to_logout?(rng_returning(0.01))).to be(true)   # < 1/30
      expect(persona.wants_to_logout?(rng_returning(0.9))).to be(false)
    end
  end

  describe "#ready_to_respond?" do
    let(:persona) { described_class.new("response_delay_minutes" => [ 2, 6 ]) }

    it "is never ready before the low bound" do
      expect(persona.ready_to_respond?(age_minutes: 1, rng: rng_returning(0.0))).to be(false)
    end

    it "is always ready past the high bound" do
      expect(persona.ready_to_respond?(age_minutes: 7, rng: rng_returning(0.99))).to be(true)
    end

    it "flips a coin inside the band" do
      expect(persona.ready_to_respond?(age_minutes: 4, rng: rng_returning(0.4))).to be(true)
      expect(persona.ready_to_respond?(age_minutes: 4, rng: rng_returning(0.6))).to be(false)
    end
  end

  describe "#decline? temperament" do
    it "meek: ducks much-stronger challengers and farmers, fights the rest" do
      persona = described_class.new("decline_style" => "meek")
      expect(persona.decline?(my_belt: 3, challenger_belt: 6, farming: false, rng: rng_returning)).to be(true)
      expect(persona.decline?(my_belt: 3, challenger_belt: 4, farming: false, rng: rng_returning)).to be(false)
      expect(persona.decline?(my_belt: 3, challenger_belt: 3, farming: true, rng: rng_returning)).to be(true)
    end

    it "proud: snubs much-weaker challengers and all farmers" do
      persona = described_class.new("decline_style" => "proud")
      expect(persona.decline?(my_belt: 6, challenger_belt: 3, farming: false, rng: rng_returning)).to be(true)
      expect(persona.decline?(my_belt: 6, challenger_belt: 7, farming: false, rng: rng_returning)).to be(false)
      expect(persona.decline?(my_belt: 6, challenger_belt: 6, farming: true, rng: rng_returning)).to be(true)
    end

    it "grudging: never declines a fair fight, only sometimes declines farming" do
      persona = described_class.new("decline_style" => "grudging")
      expect(persona.decline?(my_belt: 3, challenger_belt: 8, farming: false, rng: rng_returning)).to be(false)
      expect(persona.decline?(my_belt: 3, challenger_belt: 3, farming: true, rng: rng_returning(0.1))).to be(true)
      expect(persona.decline?(my_belt: 3, challenger_belt: 3, farming: true, rng: rng_returning(0.9))).to be(false)
    end

    it "treats an unknown style as grudging" do
      persona = described_class.new("decline_style" => "chaotic")
      expect(persona.decline_style).to eq("grudging")
    end
  end

  describe "defaults" do
    it "fills every gap when given nil config" do
      persona = described_class.new(nil)
      expect(persona.active_now?(Time.utc(2025, 1, 1, 3))).to be(true) # default window is all-day
      expect(persona.decline_style).to eq("grudging")
      expect(persona.avg_session_minutes).to eq(30.0)
    end
  end
end
