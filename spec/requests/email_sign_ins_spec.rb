require "rails_helper"

RSpec.describe "Email sign-in", type: :request do
  let(:user) { create(:user, email: "player@example.com") }

  describe "POST /sign-in/email (request a link)" do
    it "mails a link to an existing (even unverified) account" do
      user
      expect { post email_sign_in_request_path, params: { email: "player@example.com" } }
        .to change { ActionMailer::Base.deliveries.size }.by(1)
    end

    it "responds neutrally for an unknown email without sending anything" do
      expect { post email_sign_in_request_path, params: { email: "nobody@example.com" } }
        .not_to change { ActionMailer::Base.deliveries.size }
      expect(response).to redirect_to(login_path)
      expect(flash[:notice]).to be_present
    end
  end

  describe "GET /sign-in/email/:token (prefetch guard)" do
    it "renders a confirm page without consuming the token or signing in" do
      token = user.generate_token_for(:email_login)

      get email_sign_in_path(token: token)

      expect(response).to have_http_status(:ok)
      # Not signed in yet: a protected page still bounces.
      get settings_credentials_path
      expect(response).to redirect_to(login_path)
    end
  end

  describe "POST /sign-in/email/:token (confirm)" do
    it "signs the user in and verifies their email on first use" do
      token = user.generate_token_for(:email_login)

      post email_sign_in_confirm_path(token: token)

      expect(response).to redirect_to(root_path)
      expect(user.reload.email_verified?).to be(true)

      get settings_credentials_path
      expect(response).to have_http_status(:ok)
    end

    it "rejects an invalid or expired token" do
      post email_sign_in_confirm_path(token: "garbage")
      expect(response).to redirect_to(login_path)
      expect(flash[:alert]).to be_present
    end
  end
end
