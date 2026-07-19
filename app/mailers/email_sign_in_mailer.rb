class EmailSignInMailer < ApplicationMailer
  # Sends a one-tap magic link (valid 20 minutes). In this email-first app the
  # same link both signs the user in and, on first use, proves their address.
  def sign_in_link(user)
    @user = user
    @url = email_sign_in_url(token: user.generate_token_for(:email_login))

    mail(to: user.email, subject: "Your Kung Fu Madness sign-in link")
  end
end
