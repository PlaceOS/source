require "placeos-log-backend"
require "placeos-log-backend/telemetry"

require "./source/constants"

# Logging configuration
module PlaceOS::Source::Logging
  log_level = Source.production? ? Log::Severity::Info : Log::Severity::Debug
  log_backend = PlaceOS::LogBackend.log_backend

  namespaces = ["place_os.#{Source::APP_NAME}.*", "action-controller"]

  builder = ::Log.builder
  builder.bind("*", :warn, log_backend)
  namespaces.each do |namespace|
    builder.bind(namespace, log_level, log_backend)
  end

  ::Log.setup_from_env(
    default_level: log_level,
    builder: builder,
    backend: log_backend
  )

  PlaceOS::LogBackend.register_severity_switch_signals(
    production: Source.production?,
    namespaces: namespaces,
    backend: log_backend,
  )

  PlaceOS::LogBackend.configure_opentelemetry(
    service_name: APP_NAME,
    service_version: VERSION,
  )
end
