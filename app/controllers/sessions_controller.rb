class SessionsController < ApplicationController
  def new
  end

  # Issues usernameless WebAuthn assertion options (no allowCredentials), letting
  # the browser offer any discoverable passkey for this site. #create identifies
  # the user from the credential that signs the challenge.
  def options
    get_options = WebAuthn::Credential.options_for_get(user_verification: "preferred")

    session[:authentication] = { challenge: get_options.challenge }

    render json: get_options
  end

  # Verifies the passkey assertion, resolves the user from the credential, and
  # signs them in.
  def create
    authentication = session[:authentication]

    if authentication.blank?
      return render json: { error: "Your sign-in session expired. Please try again." }, status: :unprocessable_content
    end

    webauthn_credential = WebAuthn::Credential.from_get(credential_param)
    stored_credential = Credential.find_by!(external_id: webauthn_credential.id)

    webauthn_credential.verify(
      authentication["challenge"],
      public_key: stored_credential.public_key,
      sign_count: stored_credential.sign_count
    )

    stored_credential.update!(sign_count: webauthn_credential.sign_count)

    sign_in(stored_credential.user)
    render json: { redirect_url: root_path }
  rescue WebAuthn::Error, ActiveRecord::RecordNotFound
    render json: { error: "We couldn't verify that passkey." }, status: :unprocessable_content
  end

  def destroy
    sign_out
    redirect_to login_path, notice: "You have left the dojo."
  end

  private

  def credential_param
    params.require(:credential).permit!.to_h
  end
end
