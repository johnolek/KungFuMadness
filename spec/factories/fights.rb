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

    # A settled fight with XP deltas stamped — enough to render in match history
    # and the scouting tables. Winner defaults to a draw; pass winner: to set one.
    trait :resolved do
      status { :resolved }
      resolved_at { Time.current }
      ko { false }
      challenger_xp_delta { 100 }
      opponent_xp_delta { -50 }
    end
  end
end
