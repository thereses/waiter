require 'json'
require 'slack-ruby-client'

Slack.configure do |config|
  config.token = ENV['SLACK_API_TOKEN']
  config.logger = Logger.new(STDOUT)
  config.logger.level = Logger::ERROR
end

class SlackNotifier
  def initialize(users)
    @users = users
  end

  def send_status(message)
    client = Slack::Web::Client.new
    client.auth_test
    @users.each do |user|
      client.chat_postMessage(channel: user, text: message, as_user: true)
    end
  end
end
