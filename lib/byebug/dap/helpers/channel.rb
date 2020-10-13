module Byebug
  module DAP
    # A channel for synchronously passing values between threads.
    # @api private
    class Channel
      def initialize
        @mu = Mutex.new
        @cond = ConditionVariable.new
        @closed = false
        @have = false
      end

      # Close the channel.
      def close
        @mu.synchronize {
          @closed = true
          @cond.broadcast
        }
      end

      # Pop an item off the channel. Blocks until {#push} or {#close} is called.
      # @return a value that was pushed or `nil` if the channel is closed.
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

      # Push an item onto the channel. Raises an error if the channel is closed.
      # If `timeout` is nil, blocks until {#push} or {#close} is called.
      # @param message the value to push
      # @yield called on timeout
      def push(message, timeout: nil)
        deadline = timeout + Time.now.to_f unless timeout.nil?

        synchronize_loop {
          raise RuntimeError, "Send on closed channel" if @closed

          unless @have
            @cond.signal
            @have = true
            @value = message
            return
          end

          if timeout.nil?
            @cond.wait(@mu)

          else
            remaining = deadline - Time.now.to_f
            return yield if remaining < 0

            @cond.wait(@mu, remaining)
          end
        }
      end

      private

      def synchronize_loop
        @mu.synchronize { loop { yield } }
      end
    end
  end
end
