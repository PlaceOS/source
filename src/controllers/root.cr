require "http/client"
require "./application"

require "placeos-models/version"

module PlaceOS::Source::Api
  class Root < Application
    base "/api/source/v1/"

    # healthcheck, returns JSON with status of all services
    @[AC::Route::GET("/")]
    def index : NamedTuple(healthy: Bool, services: Hash(String, NamedTuple(status: String, error: String?)))
      result = self.class.healthcheck
      unless result[:healthy]
        failed_services = result[:services].select { |_, service_info| service_info[:status] == "unhealthy" }
        error_details = failed_services.map { |service, info| "#{service}: #{info[:error]}" }.join(", ")
        Log.error { "HEALTH CHECK FAILED - #{error_details}" }
      end

      # Return 200 if all healthy, 503 (Service Unavailable) if any service is unhealthy
      render status: (result[:healthy] ? 200 : 503), json: result
    end

    @[AC::Route::GET("/version")]
    def version : PlaceOS::Model::Version
      PlaceOS::Model::Version.new(
        version: VERSION,
        build_time: BUILD_TIME,
        commit: BUILD_COMMIT,
        service: APP_NAME
      )
    end

    def self.healthcheck : NamedTuple(healthy: Bool, services: Hash(String, NamedTuple(status: String, error: String?)))
      results = Promise.all(
        Promise.defer {
          check_resource("redis") { redis.ping }
        },
        Promise.defer {
          check_resource("postgres") { pg_healthcheck }
        },
        Promise.defer {
          check_resource("influx") { influx_healthcheck }
        },
      ).get

      services = Hash(String, NamedTuple(status: String, error: String?)).new
      overall_healthy = true

      results.each do |result|
        if result[:success]
          services[result[:service]] = {status: "healthy", error: nil}
        else
          services[result[:service]] = {status: "unhealthy", error: result[:error]}
          overall_healthy = false
        end
      end

      {
        healthy:  overall_healthy,
        services: services,
      }
    end

    private def self.check_resource(service_name : String, &) : NamedTuple(service: String, success: Bool, error: String?)
      Log.trace { "healthchecking #{service_name}" }
      yield
      {service: service_name, success: true, error: nil}
    rescue exception
      error_msg = exception.message || exception.class.name
      Log.error(exception: exception) { {"connection check to #{service_name} failed"} }
      # Also log to console for Docker/K8s visibility
      Log.error { "Health check failed for #{service_name}: #{error_msg}" }
      {service: service_name, success: false, error: error_msg}
    end

    private def self.pg_healthcheck
      ::DB.connect(pg_healthcheck_url) do |db|
        db.query_all("select datname from pg_stat_activity where datname is not null", as: {String}).first?
      end
    end

    @@pg_healthcheck_url : String? = nil

    private def self.pg_healthcheck_url(timeout = 5)
      @@pg_healthcheck_url ||= begin
        url = PgORM::Settings.to_uri
        uri = URI.parse(url)
        if q = uri.query
          params = URI::Params.parse(q)
          unless params["timeout"]?
            params.add("timeout", timeout.to_s)
          end
          uri.query = params.to_s
          uri.to_s
        else
          "#{url}?timeout=#{timeout}"
        end
      end
    end

    def self.influx_healthcheck : Bool
      influx_host = INFLUX_HOST
      return false if influx_host.nil?

      HTTP::Client.new(URI.parse(influx_host)) do |client|
        client.connect_timeout = 5.seconds
        client.read_timeout = 5.seconds
        client.get("/health").success?
      end
    end

    private class_getter redis : Redis do
      StatusEvents.new_redis
    end
  end
end
