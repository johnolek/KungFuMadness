# A private stream for one fighter: the personal notifications that drive the
# live inbox — challenges received, resolved, and declined. Scoped hard to the
# subscriber's own fighter, so a socket can never listen in on someone else's mail.
class FighterChannel < ApplicationCable::Channel
  def subscribed
    fighter = current_user.fighter
    fighter ? stream_for(fighter) : reject
  end
end
