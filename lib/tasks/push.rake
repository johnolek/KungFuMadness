namespace :push do
  desc "Generate a VAPID keypair for Web Push (set the values as VAPID_PUBLIC_KEY / VAPID_PRIVATE_KEY)"
  task generate_vapid: :environment do
    key = WebPush.generate_key
    puts "VAPID_PUBLIC_KEY=#{key.public_key}"
    puts "VAPID_PRIVATE_KEY=#{key.private_key}"
  end
end
