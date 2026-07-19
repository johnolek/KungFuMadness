FactoryBot.define do
  factory :user do
    sequence(:username) { |n| "fighter#{n}" }
    sequence(:email) { |n| "fighter#{n}@example.com" }
    webauthn_id { WebAuthn.generate_user_id }
  end
end
