# Register the SMTP2GO HTTP API as an ActionMailer delivery method, selected in
# config/environments/production.rb when SMTP2GO_API_KEY is set.
#
# The settings are passed inline here rather than through
# config.action_mailer.smtp2go_settings: that config path is applied to
# ActionMailer::Base by its railtie before this runs, and the accessor it needs
# (smtp2go_settings=) only exists once add_delivery_method has defined it — a
# boot-order NoMethodError. Passing default options to add_delivery_method both
# defines the accessor and seeds it, sidestepping the ordering entirely.
#
# on_load fires once ActionMailer::Base loads (after Zeitwerk is ready), so the
# autoloaded Smtp2goDelivery constant resolves.
ActiveSupport.on_load(:action_mailer) do
  add_delivery_method :smtp2go, Smtp2goDelivery, api_key: ENV["SMTP2GO_API_KEY"]
end
