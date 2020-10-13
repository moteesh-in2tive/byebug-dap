module Byebug
  module DAP
    # `childSpawned` is a custom DAP event used to notify the client that a
    # child process has spawned.
    # @api private
    class ChildSpawnedEventBody < ::DAP::Base
      ::DAP::Event.bodies[:childSpawned] = self

      # The child process's name
      # @return [String]
      # @!attribute [r]
      property :name

      # The child's process ID
      # @return [Number]
      # @!attribute [r]
      property :pid

      # The debug socket to connect to
      # @return [String]
      # @!attribute [r]
      property :socket
    end
  end
end
