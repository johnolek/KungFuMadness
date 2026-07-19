FactoryBot.define do
  factory :push_subscription do
    user
    sequence(:endpoint) { |n| "https://push.example.com/endpoint/#{n}" }
    p256dh_key { "BExampleP256dhKeyValue" }
    auth_key { "ExampleAuthKey" }
    user_agent { "Mozilla/5.0 (Test)" }
  end
end
