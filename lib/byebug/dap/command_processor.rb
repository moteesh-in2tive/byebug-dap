module Byebug
  module DAP
    class CommandProcessor
      extend Forwardable
      include SafeHelpers

      class TimeoutError < StandardError
        attr_reader :context

        def initialize(context)
          @context = context
        end
      end

      attr_reader :context
      attr_writer :pause_requested

      def initialize(context, session)
        @context = context
        @session = session
        @requests = Channel.new
        @exec_mu = Mutex.new
        @exec_ch = Channel.new
      end

      def log(*args)
        @session.log(*args)
      end

      def <<(message)
        @requests.push(message, timeout: 1) { raise TimeoutError.new(context) }
      end

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

        @session.invalidate_handles!

      rescue StandardError => e
        log "\n! #{e.message} (#{e.class})", *e.backtrace
      end

      def stopped!
        case context.stop_reason
        when :breakpoint
          args = {
            reason: 'breakpoint',
            description: 'Hit breakpoint',
            text: "Stopped by breakpoint at #{context.frame.file}:#{context.frame.line}",
          }

        when :catchpoint
          # TODO this is probably not the right message
          args = {
            reason: 'catchpoint',
            description: 'Hit catchpoint',
            text: "Stopped by catchpoint at #{context.location}: `#{@at_catchpoint}'",
          }

        when :step
          if @pause_requested
            @pause_requested = false
            args = {
              reason: 'pause',
              text: "Paused at #{context.frame.file}:#{context.frame.line}"
            }
          else
            args = {
              reason: 'step',
              text: "Stepped at #{context.frame.file}:#{context.frame.line}"
            }
          end

        else
          log "Stopped for unknown reason: #{context.stop_reason}"
        end

        @session.event! 'stopped', threadId: context.thnum, **args if args

        process_requests
      end

      alias at_line stopped!
      alias at_end stopped!

      def at_end
        stopped!
      end

      def at_return(return_value)
        @at_return = return_value
        stopped!
      end

      # def at_tracing
      #   @session.puts "Tracing: #{context.full_location}"

      #   # run_auto_cmds(2)
      # end

      def at_breakpoint(breakpoint)
        @at_breakpoint = breakpoint
      end

      def at_catchpoint(exception)
        @at_catchpoint = exception
      end
    end
  end
end
