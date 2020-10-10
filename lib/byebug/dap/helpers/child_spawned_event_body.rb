module Byebug
  module DAP
    class ChildSpawnedEventBody < ::DAP::Base
      ::DAP::Event.bodies[:childSpawned] = self

      property :name
      property :pid
      property :socket
    end
  end
end
