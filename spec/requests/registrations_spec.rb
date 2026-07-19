require "rails_helper"

RSpec.describe "Registrations (sign-up)", type: :request do
  describe "GET /sign-up" do
    it "renders the join form" do
      get signup_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /sign-up (email-first)" do
    let(:params) { { username: "IronMantis", email: "iron@example.com" } }

    it "creates an unverified user with an auto-created white-belt fighter" do
      expect { post signup_path, params: params }.to change(User, :count).by(1)

      user = User.find_by(username: "IronMantis")
      expect(user.email_verified?).to be(false)
      expect(user.fighter.name).to eq("IronMantis")
      expect(user.fighter.belt).to eq(1)
      expect(user.fighter.xp).to eq(0)
    end

    it "sends a magic sign-in link" do
      expect { post signup_path, params: params }
        .to change { ActionMailer::Base.deliveries.size }.by(1)

      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq([ "iron@example.com" ])
    end

    it "redirects with a neutral check-your-email notice" do
      post signup_path, params: params
      expect(response).to redirect_to(login_path)
      expect(flash[:notice]).to include("iron@example.com")
    end

    context "when the email is already registered" do
      let!(:existing) { create(:user, email: "iron@example.com", username: "SomeoneElse") }

      it "does not create a duplicate account" do
        expect { post signup_path, params: params.merge(username: "DifferentName") }
          .not_to change(User, :count)
      end

      it "still responds neutrally and mails the real owner a link" do
        expect { post signup_path, params: params.merge(username: "DifferentName") }
          .to change { ActionMailer::Base.deliveries.size }.by(1)

        expect(response).to redirect_to(login_path)
        expect(ActionMailer::Base.deliveries.last.to).to eq([ "iron@example.com" ])
      end
    end

    context "with a taken username" do
      before { create(:user, username: "IronMantis") }

      it "surfaces the error (the fighter name is public)" do
        post signup_path, params: params.merge(email: "new@example.com")
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "with an invalid email" do
      it "re-renders with an error" do
        post signup_path, params: { username: "Fresh", email: "not-an-email" }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
