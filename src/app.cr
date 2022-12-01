require "option_parser"

require "./config"
require "./source/constants"

module PlaceOS::Source
  # Server defaults
  host = DEFAULT_HOST
  port = DEFAULT_PORT

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

    parser.on("-d", "--docs", "Outputs OpenAPI documentation for this service") do
      puts ActionController::OpenAPI.generate_open_api_docs(
        title: PlaceOS::Source::APP_NAME,
        version: PlaceOS::Source::VERSION,
        description: "PlaceOS Source Service, saves state to InfluxDB and handles MQTT output"
      ).to_yaml
      exit 0
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

  publisher_managers = [] of PublisherManager

  publisher_managers << MqttBrokerManager.new

  influx_host, influx_api_key = INFLUX_HOST, INFLUX_API_KEY

  # Add Influx to sources if adequate environmental configuration is present
  publisher_managers << InfluxManager.new(influx_host, influx_api_key) unless influx_host.nil? || influx_api_key.nil?

  # Configure the database connection. First check if PG_DATABASE_URL environment variable
  # is set. If not, assume database configuration are set via individual environment variables
  if pg_url = ENV["PG_DATABASE_URL"]?
    PgORM::Database.parse(pg_url)
  else
    PgORM::Database.configure { |_| }
  end

  # Start application manager
  manager = Manager.new(publisher_managers)
  manager.start

  Manager.instance = manager

  # Server Configuration

  server = ActionController::Server.new(port, host)

  terminate = Proc(Signal, Nil).new do |signal|
    Log.info { "terminating gracefully" }
    spawn { server.close }
    signal.ignore
  end

  # Detect ctr-c to shutdown gracefully
  # Docker containers use the term signal
  Signal::INT.trap &terminate
  Signal::TERM.trap &terminate

  # Start the server
  server.run do
    Log.info { "listening on #{server.print_addresses}" }
  end

  # Shutdown message
  puts "#{APP_NAME} leaps through the veldt\n"
end
