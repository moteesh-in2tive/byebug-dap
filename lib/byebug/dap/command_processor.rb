module Byebug
  module DAP
    # Processes thread-specific commands and handles Byebug/TracePoint events.
    class CommandProcessor
      extend Forwardable
      include SafeHelpers

      # Indicates a timeout while sending a message to the context.
      class TimeoutError < StandardError
        # The receiving context.
        # @return [gem:byebug:Byebug::Context]
        attr_reader :context

        def initialize(context)
          @context = context
        end
      end

      # The thread context.
      # @return [gem:byebug:Byebug::Context]
      attr_reader :context

      # The last exception that occured.
      # @return [std:Exception]
      attr_reader :last_exception

      # Indicates that the client requested a pause.
      # @return [Boolean]
      # @note This should only be set by {Command::Pause}
      # @api private
      attr_writer :pause_requested

      # Create a new command processor.
      # @param context [gem:byebug:Byebug::Context] the thread context
      # @param session [Session] the debugging session
      # @note This should only be used by Byebug internals
      # @api private
      def initialize(context, session)
        @context = context
        @session = session
        @requests = Channel.new
        @exec_mu = Mutex.new
        @exec_ch = Channel.new
      end

      # (see Session#log)
      def log(*args)
        @session.log(*args)
      end

      # Send a message to the thread context.
      # @param message the message to send
      # @note Raises a {TimeoutError timeout error} after 1 second if the thread is not paused or not responding.
      def <<(message)
        @requests.push(message, timeout: 1) { raise TimeoutError.new(context) }
      end

      # Execute a code block in the thread.
      # @yield the code block to execute
      # @note This calls {#\<\<} and thus may raise a {TimeoutError timeout error}.
      def execute(&block)
        raise "Block required" unless block_given?

        r, err = nil, nil
        @exec_mu.synchronize {
          self << block
          r, err = @exec_ch.pop
        }

        if err
          raise err
        else
          r
        end
      end

      # Line handler.
      # @note This should only be called by Byebug internals
      # @api private
      def at_line
        stopped!
      end

      # End of class/module handler.
      # @note This should only be called by Byebug internals
      # @api private
      def at_end
        stopped!
      end

      # Return handler.
      # @note This should only be called by Byebug internals
      # @api private
      def at_return(return_value)
        @at_return = return_value
        stopped!
      end

      # Tracing handler.
      # @note This should only be called by Byebug internals
      # @api private
      def at_tracing
        # @session.puts "Tracing: #{context.full_location}"
      end

      # Breakpoint handler.
      # @note This should only be called by Byebug internals
      # @api private
      def at_breakpoint(breakpoint)
        @last_breakpoint = breakpoint
      end

      # Catchpoint handler.
      # @note This should only be called by Byebug internals
      # @api private
      def at_catchpoint(exception)
        @last_exception = exception
      end

      private

      def process_requests
        loop do
          request = @requests.pop
          break unless request

          if request.is_a?(Proc)
            err = nil
            r = safe(request, :call) { |e| err = e; nil }
            @exec_ch.push [r, err]
            next
          end

          break if ContextualCommand.execute(@session, request, self) == :stop
        end

        @last_exception = nil
        @session.invalidate_handles!

      rescue StandardError => e
        log "\n! #{e.message} (#{e.class})", *e.backtrace
      end

      def stopped!
        return if logpoint!

        case context.stop_reason
        when :breakpoint
          args = {
            reason: 'breakpoint',
            description: 'Hit breakpoint',
            text: "Hit breakpoint at #{context.location}",
          }

        when :catchpoint
          args = {
            reason: 'exception',
            description: 'Hit catchpoint',
            text: "Hit catchpoint at #{context.location}",
          }

        when :step
          if @pause_requested
            @pause_requested = false
            args = {
              reason: 'pause',
              description: 'Paused',
              text: "Paused at #{context.location}"
            }
          else
            args = {
              reason: 'step',
              description: 'Stepped',
              text: "Stepped at #{context.location}"
            }
          end

        else
          log "Stopped for unknown reason: #{context.stop_reason}"
        end

        @session.event! 'stopped', threadId: context.thnum, **args if args

        process_requests
      end

      def logpoint!
        return false unless @last_breakpoint

        breakpoint, @last_breakpoint = @last_breakpoint, nil
        expr = @session.get_log_point(breakpoint)
        return false unless expr

        binding = @context.frame._binding
        msg = expr.gsub(/\{([^\}]+)\}/) do |x|
          safe(binding, :eval, x[1...-1]) { return true } # ignore bad log points
        end

        body = {
          category: 'console',
          output: msg + "\n",
        }

        if breakpoint.pos.is_a?(Integer)
          body[:line] = breakpoint.pos
          body[:source] = {
            name: File.basename(breakpoint.source),
            path: breakpoint.source,
          }
        end

        @session.event! 'output', **body
        return true
      end
    end
  end
end
