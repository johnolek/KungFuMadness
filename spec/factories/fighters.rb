FactoryBot.define do
  # A standalone fighter with no user. Human fighters are created through User's
  # after_create hook (which owns the user_id), so the factory stays userless to
  # avoid colliding on the unique user_id.
  factory :fighter do
    sequence(:name) { |n| "Fighter #{n}" }
    xp { 0 }
    belt { 1 }

    trait :bot do
      bot { true }
      sequence(:name) { |n| "Bot #{n}" }
      strategy { { "type" => "biased" } }
    end
  end
end
