require "rails_helper"

# Exercises the ApplicationController gate that Phase 2 game actions sit behind,
# via an anonymous controller so no real game route is needed yet.
RSpec.describe ApplicationController, type: :controller do
  controller do
    before_action :require_verified_fighter

    def index
      render plain: "in the dojo"
    end
  end

  before { routes.draw { get "index" => "anonymous#index" } }

  context "when signed out" do
    it "redirects to sign-in" do
      get :index
      expect(response).to redirect_to(login_path)
    end
  end

  context "when signed in but unverified" do
    let(:user) { create(:user) }

    it "redirects home with a verify-your-email flash" do
      session[:user_id] = user.id
      get :index
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to be_present
    end
  end

  context "when signed in and verified" do
    let(:user) { create(:user, email_verified_at: Time.current) }

    it "allows the action through" do
      session[:user_id] = user.id
      get :index
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("in the dojo")
    end
  end
end
