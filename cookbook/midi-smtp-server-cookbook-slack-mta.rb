require 'midi-smtp-server'
require 'slack-notifier'
require 'openssl'
require 'mail'
require 'oga'

# get the slack endpoint from ENV var
SLACK_WEBHOOK = ENV['SLACK_WEBHOOK'].freeze

# check for valid settings
raise 'Missing SLACK_WEBHOOK env setting for startup.' if SLACK_WEBHOOK.to_s == ''

# Server class
class MySlackGateway < MidiSmtpServer::Smtpd

  # get each message after DATA <message> .
  def on_message_data_event(ctx)
    # Output for debug
    logger.debug("mail reveived at: [#{ctx[:server][:local_ip]}:#{ctx[:server][:local_port]}] from: [#{ctx[:envelope][:from]}] for recipient(s): [#{ctx[:envelope][:to]}]...")

    # Just decode message ones to make sure, that this message is usable
    @mail = Mail.read_from_string(ctx[:message][:data])

    # check for text message
    if @mail.text_part
      # use only plain text message
      s_text = @mail.text_part.body
    elsif @mail.html_part
      # extract text from html message
      doc = Oga.parse_html(@mail.html_part.body.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '').delete("\000"))
      # index to body node
      body_node = doc.xpath('/html/body').first
      # get plain text from dom
      s_text = body_node.text.strip if body_node
    else
      # use the simple decoded body
      s_text = @mail.body.decoded
    end

    # open channel to slack webhook
    slack_notifier = Slack::Notifier.new SLACK_WEBHOOK

    # post message to channel
    slack_notifier.post \
      attachments: [
        {
          author_name: @mail[:from],
          title: @mail.subject,
          text: s_text.to_s.force_encoding('UTF-8'),
          footer: 'MySlackGateway',
          footer_icon: 'https://4commerce-technologies-ag.github.io/midi-smtp-server/img/midi-smtp-server-logo.png',
          ts: @mail.date.to_time.to_i - @mail.date.to_time.utc_offset
        }
      ]

    # handle incoming mail, just show the message source
    logger.debug('message was pushed to slack')
  end

end

# try to gracefully shutdown on Ctrl-C
trap('INT') do
  puts 'Interrupted, exit now...'
  exit 0
end

# Output for debug
puts "#{Time.now}: Starting MySlackGateway [#{MidiSmtpServer::VERSION::STRING}|#{MidiSmtpServer::VERSION::DATE}] ..."

# Create a new server instance listening at localhost interfaces 127.0.0.1:2525
# and accepting a maximum of 4 simultaneous connections
server = MySlackGateway.new

# setup exit code
at_exit do
  # check to shutdown connection
  if server
    # Output for debug
    puts "#{Time.now}: Shutdown MySlackGateway..."
    # stop all threads and connections gracefully
    server.stop
  end
  # Output for debug
  puts "#{Time.now}: MySlackGateway down!\n"
end

# Start the server
server.start

# Run on server forever
server.join
