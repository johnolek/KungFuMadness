module ApplicationCable
  # Cable subscribers must be signed in. Auth mirrors the HTTP side: the encrypted
  # session cookie carries the user id, so a socket is exactly as trusted as the
  # page that opened it. Anonymous connections are rejected outright.
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user || reject_unauthorized_connection
    end

    private

    # @return [User, nil]
    def find_verified_user
      session = cookies.encrypted[Rails.application.config.session_options.fetch(:key)]
      User.find_by(id: session&.[]("user_id"))
    end
  end
end
