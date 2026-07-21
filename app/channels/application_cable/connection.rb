module ApplicationCable
  # Auth mirrors the HTTP side: the encrypted session cookie carries the user id,
  # so a socket is exactly as trusted as the page that opened it. Anonymous
  # connections are allowed with a nil current_user — the public DojoChannel
  # serves signed-out spectators; channels carrying personal state must reject
  # nil themselves (FighterChannel does).
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    # @return [User, nil]
    def find_verified_user
      session = cookies.encrypted[Rails.application.config.session_options.fetch(:key)]
      User.find_by(id: session&.[]("user_id"))
    end
  end
end
