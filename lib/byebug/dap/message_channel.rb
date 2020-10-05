module Byebug
  module DAP
    class MessageChannel
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
            @cond.signal
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
            @cond.signal
            @have = true
            @value = message
            return
          end

          remaining = deadline - Time.now.to_f
          return yield if remaining < 0

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
