# Passwordless email sign-in. In this email-first app the magic link is also the
# verification path: consuming it signs the user in and, on first use, stamps the
# address verified. Works on any domain, so it's the recovery path when a passkey
# can't be used too.
class EmailSignInsController < ApplicationController
  # POST /sign-in/email — email a sign-in link for the given address.
  def create
    email = params[:email].to_s.strip.downcase
    user = User.find_by("lower(email) = ?", email) if email.present?

    # Send to any existing account, verified or not — the link is how an unproven
    # address gets proven. Neutral response either way so the form never reveals
    # who has an account.
    EmailSignInMailer.sign_in_link(user).deliver_now if user

    redirect_to login_path, notice: "If that email has an account, a sign-in link is on its way."
  end

  # GET /sign-in/email/:token — render a confirm page rather than consuming the
  # token, so email link prefetchers don't spend it. The real click POSTs #confirm.
  def show
    @token = params[:token]
    render :show
  end

  # POST /sign-in/email/:token — consume the token, sign in, and verify the email.
  def confirm
    user = User.find_by_token_for(:email_login, params[:token])

    if user
      user.update!(email_verified_at: Time.current) unless user.email_verified?
      sign_in(user)
      redirect_to root_path, notice: "Signed in. Welcome to the dojo."
    else
      redirect_to login_path, alert: "That sign-in link is invalid or has expired."
    end
  end
end
