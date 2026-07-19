require "rails_helper"

RSpec.describe "Sessions (passkey auth)", type: :request do
  describe "GET /sign-in" do
    it "renders the sign-in page" do
      get login_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "passkey registration and sign-in round trip" do
    it "registers a passkey at signup and creates the user + fighter" do
      expect { register_passkey(username: "Crane") }.to change(User, :count).by(1)

      expect(response).to have_http_status(:ok)
      user = User.find_by(username: "Crane")
      expect(user.credentials.count).to eq(1)
      expect(user.fighter.name).to eq("Crane")
    end

    it "authenticates a returning fighter with their discoverable passkey" do
      register_passkey(username: "Crane")
      delete logout_path

      authenticate_passkey

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["redirect_url"]).to eq(root_path)
    end

    it "rejects a create with no pending challenge" do
      post login_path, params: { credential: { fake: true } }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /sign-out" do
    it "signs the user out" do
      register_passkey(username: "Crane")
      delete logout_path
      expect(response).to redirect_to(login_path)
    end
  end
end
