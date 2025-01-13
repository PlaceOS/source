require "./logging"

# Application dependencies
require "action-controller"

# Application code
require "./placeos-source"
require "./controllers/*"

# Server required after application controllers
require "action-controller/server"

# Add handlers that should run before your application
ActionController::Server.before(
  ActionController::ErrorHandler.new(PlaceOS::Source.production?, ["X-Request-ID"]),
  ActionController::LogHandler.new
)
