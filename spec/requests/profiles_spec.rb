require "rails_helper"

RSpec.describe "Profiles", type: :request do
  let(:user) { create(:user) }

  describe "PATCH /profile" do
    context "as a verified fighter" do
      before { sign_in_as(user) }

      it "saves a bio and shows it publicly on the profile" do
        patch profile_path, params: { bio: "  Fear the crane style.  " }

        expect(response).to redirect_to(fighter_path(user.fighter))
        expect(user.fighter.reload.bio).to eq("Fear the crane style.")

        delete logout_path
        get fighter_path(user.fighter)
        expect(response.body).to include("Fear the crane style.")
      end

      it "attaches an uploaded portrait" do
        patch profile_path, params: { avatar: fixture_file_upload("avatar.png", "image/png") }

        expect(user.fighter.reload.avatar).to be_attached
      end

      it "rejects a non-image upload without attaching" do
        patch profile_path, params: { avatar: fixture_file_upload("not_an_image.txt", "text/plain") }

        follow_redirect!
        expect(user.fighter.reload.avatar).not_to be_attached
      end

      it "removes the portrait on request" do
        patch profile_path, params: { avatar: fixture_file_upload("avatar.png", "image/png") }
        expect(user.fighter.reload.avatar).to be_attached

        patch profile_path, params: { remove_avatar: "1", bio: user.fighter.bio }
        expect(user.fighter.reload.avatar).not_to be_attached
      end

      it "clears the bio when blanked" do
        user.fighter.update!(bio: "old words")

        patch profile_path, params: { bio: "" }

        expect(user.fighter.reload.bio).to be_nil
      end
    end

    context "when signed out" do
      it "changes nothing" do
        patch profile_path, params: { bio: "sneaky" }

        expect(response).to have_http_status(:redirect)
        expect(user.fighter.reload.bio).to be_nil
      end
    end
  end
end
