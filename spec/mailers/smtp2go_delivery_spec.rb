require "rails_helper"

RSpec.describe Smtp2goDelivery do
  subject(:delivery) { described_class.new(api_key: "api-test") }

  let(:mail) do
    Mail.new do
      from    "john@johnoleksowicz.com"
      to      "recipient@example.com"
      subject "Your sign-in link"
      text_part { body "text version" }
      html_part do
        content_type "text/html; charset=UTF-8"
        body "<p>html version</p>"
      end
    end
  end

  def response(code:, body:)
    instance_double(Net::HTTPResponse, code: code.to_s, body: body)
  end

  def succeeded_body
    { data: { succeeded: 1, failed: 0, email_id: "abc-123" } }.to_json
  end

  it "maps the mail into the SMTP2GO API payload" do
    captured = nil
    allow(delivery).to receive(:post) { |payload| captured = payload; response(code: 200, body: succeeded_body) }

    delivery.deliver!(mail)

    expect(captured).to include(
      sender: "john@johnoleksowicz.com",
      to: [ "recipient@example.com" ],
      subject: "Your sign-in link"
    )
    expect(captured[:text_body]).to include("text version")
    expect(captured[:html_body]).to include("<p>html version</p>")
  end

  it "logs the email_id on success and does not raise" do
    allow(delivery).to receive(:post).and_return(response(code: 200, body: succeeded_body))
    expect(Rails.logger).to receive(:info).with(/email_id=abc-123/)

    expect { delivery.deliver!(mail) }.not_to raise_error
  end

  it "raises and logs when the API reports a failure" do
    body = { data: { succeeded: 0, failed: 1, error: "sender not verified" } }.to_json
    allow(delivery).to receive(:post).and_return(response(code: 400, body: body))
    expect(Rails.logger).to receive(:error).with(/FAILED.*sender not verified/)

    expect { delivery.deliver!(mail) }.to raise_error(Smtp2goDelivery::DeliveryError, /HTTP 400/)
  end
end
