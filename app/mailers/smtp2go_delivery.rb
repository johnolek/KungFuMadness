require "net/http"
require "json"

# ActionMailer delivery method that sends through the SMTP2GO HTTP API instead
# of SMTP. We get an explicit, logged success/failure (HTTP 200 + JSON
# "succeeded": 1 with an email_id) rather than SMTP's swallowed 250, and it runs
# over HTTPS/443 so there's no STARTTLS/port negotiation to misconfigure.
#
# Registered as :smtp2go in config/initializers/smtp2go.rb; selected in
# production when SMTP2GO_API_KEY is present (else we fall back to SMTP).
class Smtp2goDelivery
  ENDPOINT = URI("https://api.smtp2go.com/v3/email/send").freeze
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 15

  class DeliveryError < StandardError; end

  attr_reader :settings

  def initialize(settings)
    @settings = settings
  end

  def deliver!(mail)
    response = post(build_payload(mail))
    handle(response, mail)
  end

  private

  def build_payload(mail)
    text, html = bodies(mail)
    {
      sender: mail[:from]&.formatted&.first || mail.from&.first,
      to: mail[:to]&.formatted || Array(mail.to),
      subject: mail.subject,
      text_body: text,
      html_body: html
    }.compact
  end

  # SMTP2GO wants the parts as separate fields; our mailers are multipart
  # (html + text), but handle the single-part cases too.
  def bodies(mail)
    if mail.multipart?
      [ mail.text_part&.decoded, mail.html_part&.decoded ]
    elsif mail.mime_type == "text/html"
      [ nil, mail.body.decoded ]
    else
      [ mail.body.decoded, nil ]
    end
  end

  def post(payload)
    http = Net::HTTP.new(ENDPOINT.host, ENDPOINT.port)
    http.use_ssl = true
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT

    request = Net::HTTP::Post.new(ENDPOINT)
    request["Content-Type"] = "application/json"
    request["Accept"] = "application/json"
    request["X-Smtp2go-Api-Key"] = settings[:api_key]
    request.body = payload.to_json

    http.request(request)
  end

  # Log either way so there's always a breadcrumb, then raise on failure so the
  # error also surfaces wherever raise_delivery_errors is on.
  def handle(response, mail)
    data = (JSON.parse(response.body)["data"] rescue nil) || {}
    recipients = Array(mail.to).join(", ")

    if success?(response) && data["succeeded"].to_i >= 1
      Rails.logger.info(
        "[smtp2go] delivered #{mail.subject.inspect} to #{recipients} email_id=#{data['email_id']}"
      )
    else
      detail = data["error"] || data["failures"].presence || response.body
      Rails.logger.error(
        "[smtp2go] delivery FAILED (HTTP #{response.code}) to #{recipients}: #{detail}"
      )
      raise DeliveryError, "SMTP2GO send failed (HTTP #{response.code}): #{detail}"
    end
  end

  def success?(response)
    response.code.to_i.between?(200, 299)
  end
end
