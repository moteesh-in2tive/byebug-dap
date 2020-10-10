module Byebug
  module DAP
    class Handles
      def initialize
        @mu = Mutex.new
        @entries = []
      end

      def clear!
        sync { @entries = []; nil }
      end

      def [](id)
        sync { @entries[id-1] }
      end

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
