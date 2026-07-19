class RegistrationsController < ApplicationController
  def new
    @user = User.new
  end

  # Email-first signup: create the (unverified) account and email a magic link
  # that both signs the user in and proves their address on first use. The
  # response never reveals whether an email was already registered — if it was,
  # the real owner still gets a link, and the reply is identical either way.
  # Username problems are surfaced normally: it's the public fighter name.
  def create
    username = params[:username].to_s.strip
    email = params[:email].to_s.strip.downcase
    @user = User.new(username: username, email: email, webauthn_id: WebAuthn.generate_user_id)

    if username.blank?
      @user.errors.add(:username, "is required")
      return render :new, status: :unprocessable_content
    end
    if User.exists?(username: username)
      @user.errors.add(:username, "is already taken")
      return render :new, status: :unprocessable_content
    end
    if email.blank? || !email.match?(URI::MailTo::EMAIL_REGEXP)
      @user.errors.add(:email, "must be a valid email address")
      return render :new, status: :unprocessable_content
    end

    if (existing = User.find_by("lower(email) = ?", email))
      EmailSignInMailer.sign_in_link(existing).deliver_now
    elsif @user.save
      EmailSignInMailer.sign_in_link(@user).deliver_now
    end

    redirect_to login_path,
                notice: "Almost there — we sent a sign-in link to #{email}. Open it within 20 minutes to enter the dojo."
  end

  # Issues WebAuthn credential-creation options and stashes the challenge for
  # #create_passkey. The optional "set up a passkey now" path on signup.
  def options
    username = params[:username].to_s.strip
    email = params[:email].to_s.strip.downcase

    if username.blank?
      return render json: { error: "Please choose a username." }, status: :unprocessable_content
    end
    if User.exists?(username: username)
      return render json: { error: "That username is taken." }, status: :unprocessable_content
    end
    if email.blank? || !email.match?(URI::MailTo::EMAIL_REGEXP)
      return render json: { error: "Please enter a valid email address." }, status: :unprocessable_content
    end

    webauthn_id = WebAuthn.generate_user_id
    create_options = WebAuthn::Credential.options_for_create(
      user: { id: webauthn_id, name: username, display_name: username },
      authenticator_selection: { user_verification: "preferred", resident_key: "required" }
    )

    session[:registration] = {
      challenge: create_options.challenge,
      username: username,
      webauthn_id: webauthn_id,
      email: email
    }

    render json: create_options
  end

  # Verifies the new passkey, creates the user (and their fighter, via the model
  # hook), emails the verification/sign-in link, and signs them in. Email still
  # needs verifying before they can fight.
  def create_passkey
    registration = session[:registration]

    if registration.blank?
      return render json: { error: "Your registration session expired. Please try again." }, status: :unprocessable_content
    end

    webauthn_credential = WebAuthn::Credential.from_create(credential_param)
    webauthn_credential.verify(registration["challenge"])

    user = User.new(username: registration["username"], webauthn_id: registration["webauthn_id"], email: registration["email"])
    user.credentials.build(
      external_id: webauthn_credential.id,
      public_key: webauthn_credential.public_key,
      sign_count: webauthn_credential.sign_count,
      nickname: params[:nickname].presence
    )
    user.save!
    EmailSignInMailer.sign_in_link(user).deliver_now

    sign_in(user)
    render json: { redirect_url: root_path }
  rescue WebAuthn::Error => e
    render json: { error: "Passkey could not be verified: #{e.message}" }, status: :unprocessable_content
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_content
  end

  private

  def credential_param
    params.require(:credential).permit!.to_h
  end
end
