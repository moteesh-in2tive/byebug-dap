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

      attr_reader :context, :interface

      def initialize(context, interface)
        @context = context
        @interface = interface
        @requests = Channel.new
        @exec_mu = Mutex.new
        @exec_ch = Channel.new
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

          case request.command
          when 'continue'
            # "The request starts the debuggee to run again.

            break

          when 'pause'
            # "The request suspends the debuggee.
            # "The debug adapter first sends the response and then a ‘stopped’ event (with reason ‘pause’) after the thread has been paused successfully.

            @pause_requested = true

          when 'next'
            # "The request starts the debuggee to run again for one step.
            # "The debug adapter first sends the response and then a ‘stopped’ event (with reason ‘step’) after the step has completed.

            context.step_over(1, context.frame.pos)
            break

          when 'stepIn'
            # "The request starts the debuggee to step into a function/method if possible.
            # "If it cannot step into a target, ‘stepIn’ behaves like ‘next’.
            # "The debug adapter first sends the response and then a ‘stopped’ event (with reason ‘step’) after the step has completed.
            # "If there are multiple function/method calls (or other targets) on the source line,
            # "the optional argument ‘targetId’ can be used to control into which target the ‘stepIn’ should occur.
            # "The list of possible targets for a given source line can be retrieved via the ‘stepInTargets’ request.

            context.step_into(1, context.frame.pos)
            break

          when 'stepOut'
            # "The request starts the debuggee to run again for one step.
            # "The debug adapter first sends the response and then a ‘stopped’ event (with reason ‘step’) after the step has completed.

            context.step_out(context.frame.pos + 1, false)
            context.frame = 0
            break
          end
        end

        interface.invalidate_handles!

      rescue StandardError => e
        STDERR.puts "\n! #{e.message} (#{e.class})", *e.backtrace
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
          STDERR.puts "Stopped for unknown reason: #{context.stop_reason}"
        end

        interface.event! 'stopped', threadId: context.thnum, **args if args

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
      #   interface.puts "Tracing: #{context.full_location}"

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
