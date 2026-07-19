require "rails_helper"

RSpec.describe "Settings::Credentials", type: :request do
  before { register_passkey(username: "owner") }

  let(:user) { User.find_by(username: "owner") }

  # Runs the authenticated add-passkey handshake with a fresh authenticator.
  def add_passkey(nickname: nil, client: WebAuthn::FakeClient.new(webauthn_origin))
    post options_settings_credentials_path, as: :json
    challenge = response.parsed_body["challenge"]
    credential = client.create(challenge: challenge, user_verified: true)
    post settings_credentials_path, params: { credential: credential, nickname: nickname }, as: :json
  end

  describe "GET /settings/credentials" do
    it "lists the current user's passkeys" do
      get settings_credentials_path
      expect(response).to have_http_status(:ok)
    end

    it "requires a signed-in user" do
      delete logout_path
      get settings_credentials_path
      expect(response).to redirect_to(login_path)
    end
  end

  describe "adding a passkey" do
    it "enrolls an additional passkey for the current user" do
      expect { add_passkey(nickname: "Backup key") }.to change { user.credentials.count }.by(1)
      expect(response).to have_http_status(:ok)
      expect(user.credentials.order(:created_at).last.nickname).to eq("Backup key")
    end

    it "rejects a create with no pending challenge" do
      post settings_credentials_path, params: { credential: { fake: true } }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "removing a passkey" do
    it "revokes a passkey when more than one remains" do
      add_passkey
      extra = user.credentials.order(:created_at).last
      expect { delete settings_credential_path(extra) }.to change { user.credentials.count }.by(-1)
      expect(response).to redirect_to(settings_credentials_path)
    end

    it "allows removing the last passkey (email is the recovery path)" do
      only = user.credentials.first
      expect { delete settings_credential_path(only) }.to change { user.credentials.count }.by(-1)
      expect(response).to redirect_to(settings_credentials_path)
    end
  end
end
