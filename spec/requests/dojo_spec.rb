require "rails_helper"

RSpec.describe "Dojo", type: :request do
  describe "GET /" do
    it "renders a signed-out intro with join links" do
      get root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("The Dojo")
      expect(response.body).to include(signup_path)
    end

    it "shows a verified fighter their inbox and recent fights" do
      user = create(:user)
      sign_in_as(user)

      get root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Challenges to answer")
      expect(response.body).to include("Recent fights across the dojo")
    end
  end
end
