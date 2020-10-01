module Byebug
  module DAP
    class CommandProcessor
      extend Forwardable

      attr_reader :context, :interface

      def_delegators :@context, :frame

      def initialize(context, interface)
        @context = context
        @interface = interface
        @proceed = false
      end

      def proceed!
        @proceed = true
      end

      def at_line
        process_commands
      end

      def at_tracing
        interface.puts "Tracing: #{context.full_location}"

        # run_auto_cmds(2)
      end

      def at_breakpoint(brkpt)
        number = Byebug.breakpoints.index(brkpt) + 1

        interface.puts "Stopped by breakpoint #{number} at #{frame.file}:#{frame.line}"
      end

      def at_catchpoint(exception)
        interface.puts "Catchpoint at #{context.location}: `#{exception}'"
      end

      def at_return(return_value)
        interface.puts "Return value is: #{safe_inspect(return_value)}"

        process_commands
      end

      def at_end
        process_commands
      end

      def process_commands
        @proceed = false

        until @proceed
          interface.puts(run_cmd(interface.gets))
        end
      end

      def run_cmd(request)
        response = {
          request_seq: request.seq,
          command: request.command,
        }

        case request.command
        when 'helo'
          response[:message] = 'eloh'
          response[:success] = true

        when 'interrupt'
          Byebug.start
          Byebug.thread_context(Thread.main).interrupt
          response[:success] = true

        when 'next'
          context.step_over(1, context.frame.pos)
          proceed!
          response[:success] = true

        when 'continue'
          proceed!

          Byebug.mode = :off
          Byebug.stop
          response[:success] = true

        else
          response[:success] = false
          response[:message] = 'Invalid command'
        end

        ::DAP::Response.new response
      end
    end
  end
end
