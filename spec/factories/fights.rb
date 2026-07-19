FactoryBot.define do
  factory :fight do
    association :challenger, factory: :fighter
    association :opponent, factory: :fighter
    status { :pending }
    challenger_belt { challenger.belt }
    challenger_xp { challenger.xp }
    opponent_belt { opponent.belt }
    opponent_xp { opponent.xp }
    expires_at { 7.days.from_now }
  end
end
