require "./application"

require "placeos-models/version"

module PlaceOS::Source::Api
  class Root < Application
    base "/api/source/v1/"

    # healthcheck, returns OK if all connections are good
    @[AC::Route::GET("/")]
    def index : Nil
      raise "health check failed" unless self.class.healthcheck?
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

    def self.healthcheck? : Bool
      Promise.all(
        Promise.defer {
          check_resource?("redis") { redis.ping }
        },
        Promise.defer {
          check_resource?("postgres") { pg_healthcheck }
        },
      ).then(&.all?).get
    end

    private def self.check_resource?(resource, &)
      Log.trace { "healthchecking #{resource}" }
      !!yield
    rescue exception
      Log.error(exception: exception) { {"connection check to #{resource} failed"} }
      false
    end

    private def self.pg_healthcheck
      ::DB.connect(pg_healthcheck_url) do |db|
        db.query_all("select datname, usename from pg_stat_activity where datname is not null", as: {String, String}).first?
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

    private class_getter redis : Redis do
      StatusEvents.new_redis
    end
  end
end
