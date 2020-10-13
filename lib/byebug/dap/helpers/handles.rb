module Byebug
  module DAP
    # Tracks opaque handles used by DAP.
    # @api private
    class Handles
      def initialize
        @mu = Mutex.new
        @entries = []
      end

      # Delete all handles.
      def clear!
        sync { @entries = []; nil }
      end

      # Retrieve the entry with the specified handle.
      # @param id [Integer] the handle
      # @return the entry
      def [](id)
        sync { @entries[id-1] }
      end

      # Add a new entry.
      # @return [Integer] the handle
      def <<(entry)
        sync do
          @entries << entry
          @entries.size
        end
      end

      private

      def sync
        @mu.synchronize { yield }
      end
    end
  end
end
