#!/usr/bin/env ruby
require 'uaa'
require 'json'
require 'net/smtp'

Waiter=Struct.new(:om_url, :username, :password) do
  def status
    token_issuer = CF::UAA::TokenIssuer.new(om_url + "/uaa", "opsman", nil, skip_ssl_validation: true)
    token = token_issuer.owner_password_grant(username, password).auth_header

    request = Net::HTTP::Get.new("/api/v0/installations")
    request['Authorization'] = token

    uri = URI(om_url)
    http = Net::HTTP.new(uri.host, uri.port)
    if uri.scheme == 'https'
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end

    response = http.request(request)
    JSON.parse(response.body)['installations'].first["status"]
  end

  def is_installing?
    status == "running"
  end
end

  def duration(diff)
    secs  = diff.to_int
    mins  = secs / 60
    hours = mins / 60
    days  = hours / 24

    if days > 0
      "#{days} days and #{hours % 24} hours"
    elsif hours > 0
      "#{hours} hours and #{mins % 60} minutes"
    elsif mins > 0
      "#{mins} minutes and #{secs % 60} seconds"
    elsif secs >= 0
      "#{secs} seconds"
    end
  end

waiter = Waiter.new(ENV['OM_URL'], ENV['USERNAME'], ENV['PASSWORD'])
loop do
  unless waiter.is_installing?
    sleep 60
    next
  end
  start_time = Time.now
  while waiter.is_installing?
    print "."
    sleep 30
  end

  end_time = Time.now

  class MailNotifier
    def initialize(address, port, helo, from_email, to_email, secret)
      @address = address
      @port = port
      @helo = helo
      @from_email = from_email
      @to_email = to_email
      @secret = secret
    end

    def send_status(message)
      Net::SMTP.start(@address, @port, @helo, @from_email, @secret) do |smtp|
        smtp.send_message message,
          @from_email,
          @to_email
      end
    end
  end

  class MacNotifier
    def send_status(status)
      TerminalNotifier.notify(status, title: 'OpsManager Waiter', open: ENV['OM_URL'])
    end
  end

  notifiers = []
  if ENV['FROM_EMAIL']
    notifiers << MailNotifier.new(ENV['SMTP_ADDRESS'], ENV['SMTP_PORT'], ENV['SMTP_HELO'], ENV['FROM_EMAIL'], ENV['EMAIL'], ENV['SECRET'])
  end

  if ENV['SLACK_API_TOKEN']
    require_relative 'bot'

    notifiers << SlackNotifier.new(ENV['SLACK_IDS'].split(','))
  end

  message = "Ops Manager #{ENV['OM_URL']} installation " + waiter.status + ". It took " + duration(end_time - start_time) + "."
  if RUBY_PLATFORM =~ /darwin/i
    require 'terminal-notifier'
    notifiers << MacNotifier.new
  end

  notifiers.each { |notifier| notifier.send_status(message) }
  puts
  puts message
end
