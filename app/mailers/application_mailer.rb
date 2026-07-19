class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAIL_FROM", "dojo@localhost")
  layout "mailer"
end
