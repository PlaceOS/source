require "option_parser"

require "./config"
require "./mqtt/constants"

module PlaceOS::MQTT
  # Server defaults
  host = ENV["PLACE_MQTT_HOST"]? || "127.0.0.1"
  port = (ENV["PLACE_MQTT_PORT"]? || 3000).to_i

  # Application configuration
  content_directory = nil
  update_crontab = nil
  git_username = nil
  git_password = nil

  # Command line options
  OptionParser.parse(ARGV.dup) do |parser|
    parser.banner = "Usage: #{APP_NAME} [arguments]"

    # Server flags
    parser.on("-b HOST", "--bind=HOST", "Specifies the server host") { |h| host = h }
    parser.on("-p PORT", "--port=PORT", "Specifies the server port") { |p| port = p.to_i }
    parser.on("-r", "--routes", "List the application routes") do
      ActionController::Server.print_routes
      exit 0
    end

    parser.on("-v", "--version", "Display the application version") do
      puts "#{APP_NAME} v#{VERSION}"
      exit 0
    end

    parser.on("-c URL", "--curl=URL", "Perform a basic health check by requesting the URL") do |url|
      begin
        response = HTTP::Client.get url
        exit 0 if (200..499).includes? response.status_code
        puts "health check failed, received response code #{response.status_code}"
        exit 1
      rescue error
        puts error.inspect_with_backtrace(STDOUT)
        exit 2
      end
    end

    parser.invalid_option do |flag|
      STDERR.puts "ERROR: #{flag} unrecognised"
      puts parser
      exit 1
    end

    parser.on("-h", "--help", "Show this help") do
      puts parser
      exit 0
    end
  end

  # Start application manager
  PlaceOS::MQTT::Manager.instance.start

  # Server Configuration

  server = ActionController::Server.new(port, host)

  terminate = Proc(Signal, Nil).new do |signal|
    puts " > terminating gracefully"
    spawn { server.close }
    signal.ignore
  end

  # Detect ctr-c to shutdown gracefully
  # Docker containers use the term signal
  Signal::INT.trap &terminate
  Signal::TERM.trap &terminate

  # Allow signals to change the log level at run-time
  logging = Proc(Signal, Nil).new do |signal|
    level = signal.usr1? ? Log::Severity::Debug : Log::Severity::Info
    puts " > Log level changed to #{level}"
    Log.builder.bind "*", level, LOG_BACKEND
    signal.ignore
  end

  # Turn on DEBUG level logging `kill -s USR1 %PID`
  # Default production log levels (INFO and above) `kill -s USR2 %PID`
  Signal::USR1.trap &logging
  Signal::USR2.trap &logging

  # Start the server
  server.run do
    puts "Listening on #{server.print_addresses}"
  end

  # Shutdown message
  puts "#{APP_NAME} leaps through the veldt\n"
end
