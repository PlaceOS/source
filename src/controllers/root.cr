require "./application"

module PlaceOS::Source::Api
  class Root < Application
    base "/api/source/v1/"

    def index
      head :ok
    end
  end
end
