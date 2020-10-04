module Byebug
  module DAP
    class MessageChannel
      class TimeoutError; end

      extend Forwardable

      def initialize
        @mu = Mutex.new
        @cond = ConditionVariable.new
        @closed = false
        @have = false
      end

      def close
        @mu.synchronize {
          @closed = true
          @cond.broadcast
        }
      end

      def pop
        synchronize_loop {
          return if @closed

          if @have
            @cond.broadcast
            @have = false
            return @value
          end

          @cond.wait(@mu)
        }
      end

      def push(message, timeout)
        deadline = timeout + Time.now.to_f

        synchronize_loop {
          raise RuntimeError, "Send on closed channel" if @closed

          unless @have
            @cond.broadcast
            @have = true
            @value = message
            return true
          end

          remaining = deadline - Time.now.to_f
          return false

          @cond.wait(@mu, remaining)
        }
      end

      private

      def synchronize_loop
        @mu.synchronize { loop { yield } }
      end
    end
  end
end
