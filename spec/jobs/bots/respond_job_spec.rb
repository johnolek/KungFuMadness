require "rails_helper"

RSpec.describe Bots::RespondJob, type: :job do
  def challenge(challenger:, opponent:)
    Fight.create_challenge!(
      challenger: challenger, opponent: opponent,
      moves: (1..3).map { |r| { round: r, attack_height: 2, attack_style: 0, block_height: 2 } }
    )
  end

  it "resolves a pending bot fight end to end" do
    human = create(:fighter, belt: 3, xp: 800)
    bot = create(:fighter, :bot, belt: 3, xp: 800, strategy: { "type" => "biased" })
    fight = challenge(challenger: human, opponent: bot)

    expect { described_class.perform_now(fight.id) }
      .to change { fight.reload.status }.from("pending").to("resolved")

    expect(fight.fight_rounds.count).to eq(3)
    expect(fight.fight_moves.where(fighter: bot).count).to eq(3)
    expect(human.reload.last_fought_at).to be_present
    expect(bot.reload.last_fought_at).to be_present
  end

  it "declines when the challenger has been farming the bot" do
    human = create(:fighter)
    # A proud bot always refuses a farmer, so the decline is deterministic.
    bot = create(:fighter, :bot, strategy: { "type" => "biased", "persona" => { "decline_style" => "proud" } })

    Fight::FARM_LIMIT.times do
      f = challenge(challenger: human, opponent: bot)
      f.update_columns(status: Fight.statuses[:resolved], created_at: 1.hour.ago)
    end

    fight = challenge(challenger: human, opponent: bot)

    expect { described_class.perform_now(fight.id) }
      .to change { bot.reload.declines }.by(1)
    expect(fight.reload).to be_declined
  end

  it "no-ops on a fight that isn't a pending bot challenge" do
    human_a = create(:fighter)
    human_b = create(:fighter)
    fight = challenge(challenger: human_a, opponent: human_b)

    expect { described_class.perform_now(fight.id) }.not_to change { fight.reload.status }
    expect(fight).to be_pending
  end

  it "no-ops cleanly on a missing fight id" do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end
