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
        sync { @entries[id]; nil }
      end

      def <<(entry)
        sync do
          @entries << entry
          @entry.size - 1
        end
      end

      private

      def sync
        @mu.synchronize { yield }
      end
    end
  end
end
