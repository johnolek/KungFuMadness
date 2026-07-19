# Signs a user in for request specs by driving the magic-link confirm path,
# which both signs in and stamps the email verified — so the returned session is
# a fully verified fighter able to reach the game routes.
module AuthenticationHelpers
  # @param user [User]
  def sign_in_as(user)
    user.update!(email_verified_at: Time.current) unless user.email_verified?
    token = user.generate_token_for(:email_login)
    post email_sign_in_confirm_path(token)
  end
end

RSpec.configure do |config|
  config.include AuthenticationHelpers, type: :request
end
