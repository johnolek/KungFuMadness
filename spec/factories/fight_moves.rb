FactoryBot.define do
  factory :fight_move do
    fight
    fighter { fight.challenger }
    round { 1 }
    attack_height { 2 }
    attack_style { 0 }
    block_height { 2 }
  end
end
