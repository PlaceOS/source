require "uuid"
require "action-controller"

module PlaceOS::Source::Api
  abstract class Application < ActionController::Base
    # =========================================
    # LOGGING
    # =========================================
    Log = ::Log.for(self)
    @request_id : String? = nil

    # This makes it simple to match client requests with server side logs.
    # When building microservices this ID should be propagated to upstream services.
    @[AC::Route::Filter(:before_action)]
    protected def configure_request_logging
      @request_id = request_id = request.headers["X-Request-ID"]? || UUID.random.to_s
      Log.context.set(
        client_ip: client_ip,
        request_id: request_id,
      )
      response.headers["X-Request-ID"] = request_id
    end
  end
end
