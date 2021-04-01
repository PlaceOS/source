require "placeos-log-backend"

# Logging configuration
log_level = PlaceOS::Source.production? ? Log::Severity::Info : Log::Severity::Debug
log_backend = PlaceOS::LogBackend.log_backend

# Allow signals to change the log level at run-time
logging = Proc(Signal, Nil).new do |signal|
  level = signal.usr1? ? Log::Severity::Debug : Log::Severity::Info
  puts " > Log level changed to #{level}"
  ::Log.builder.bind "place_os.#{PlaceOS::Source::APP_NAME}.*", level, log_backend
  signal.ignore
end

# Turn on DEBUG level logging `kill -s USR1 %PID`
# Default production log levels (INFO and above) `kill -s USR2 %PID`
Signal::USR1.trap &logging
Signal::USR2.trap &logging

::Log.setup "*", :warn, log_backend
::Log.builder.bind "place_os.source.*", log_level, log_backend
::Log.builder.bind "action-controller.*", log_level, log_backend
