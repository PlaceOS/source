require "placeos-log-backend"

require "./source/constants"

# Logging configuration
module PlaceOS::Source::Logging
  log_level = Source.production? ? Log::Severity::Info : Log::Severity::Debug
  log_backend = PlaceOS::LogBackend.log_backend

  namespaces = ["place_os.#{Source::APP_NAME}.*", "action-controller"]
  ::Log.setup do |config|
    config.bind "*", :warn, log_backend
    namespaces.each do |namespace|
      config.bind namespace, log_level, log_backend
    end
  end

  PlaceOS::LogBackend.register_severity_switch_signals(
    production: Source.production?,
    namespaces: namespaces,
    backend: log_backend,
  )
end
