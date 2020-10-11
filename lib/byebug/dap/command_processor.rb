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

      attr_reader :context, :last_exception
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

        @last_exception = nil
        @session.invalidate_handles!

      rescue StandardError => e
        log "\n! #{e.message} (#{e.class})", *e.backtrace
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
        @last_breakpoint = breakpoint
      end

      def at_catchpoint(exception)
        @last_exception = exception
      end
    end
  end
end
