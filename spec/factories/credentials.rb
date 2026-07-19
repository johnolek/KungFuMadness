FactoryBot.define do
  factory :credential do
    user
    sequence(:external_id) { |n| "external-id-#{n}" }
    public_key { "stored-public-key" }
    sign_count { 0 }
    nickname { "Primary passkey" }
  end
end
