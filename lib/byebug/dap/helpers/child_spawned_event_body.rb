module Byebug
  module DAP
    # `childSpawned` is a custom DAP event used to notify the client that a
    # child process has spawned.
    # @api private
    class ChildSpawnedEventBody < Protocol::Base
      Protocol::Event.bodies[:childSpawned] = self

      # The child process's name
      # @return [std:String]
      # @!attribute [r]
      property :name

      # The child's process ID
      # @return [std:Integer]
      # @!attribute [r]
      property :pid

      # The debug socket to connect to
      # @return [std:String]
      # @!attribute [r]
      property :socket
    end
  end
end
