require "rails_helper"

RSpec.describe "PWA endpoints" do
  describe "GET /manifest" do
    it "serves the web app manifest when the browser negotiates a browser-like Accept header" do
      get "/manifest", headers: { "Accept" => "application/manifest+json,*/*;q=0.8" }

      expect(response).to have_http_status(:ok)

      manifest = JSON.parse(response.body)
      expect(manifest["name"]).to eq("Kung Fu Madness")
      expect(manifest["display"]).to eq("standalone")
      expect(manifest["start_url"]).to eq("/")
      expect(manifest["icons"]).to include(
        hash_including("sizes" => "512x512", "purpose" => "maskable")
      )
    end

    it "serves JSON even on a plain HTML Accept header" do
      get "/manifest", headers: { "Accept" => "text/html" }

      expect(response).to have_http_status(:ok)
      expect { JSON.parse(response.body) }.not_to raise_error
    end
  end

  describe "GET /service-worker" do
    it "serves the service worker as JavaScript" do
      get "/service-worker", headers: { "Accept" => "*/*" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/javascript")
      expect(response.body).to include("push").and include("notificationclick")
    end
  end
end
