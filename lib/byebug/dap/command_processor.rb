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

      rescue EOFError
        proceed!
        Byebug.mode = :off
        Byebug.stop
        return
      end

      def run_cmd(request)
        response = {
          request_seq: request.seq,
          command: request.command,
        }

        case request.command
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

        when 'initialize'
          response[:success] = true
          response[:body] = {
            # we support nothing
          }

        when 'attach'
          # The attach request is sent from the client to the debug adapter to attach to a debuggee that is already running.
        when 'launch'
          # This launch request is sent from the client to the debug adapter to start the debuggee with or without debugging (if ‘noDebug’ is true).
        when 'disconnect'
          # The ‘disconnect’ request is sent from the client to the debug adapter in order to stop debugging.
          # It asks the debug adapter to disconnect from the debuggee and to terminate the debug adapter.
          # If the debuggee has been started with the ‘launch’ request, the ‘disconnect’ request terminates the debuggee.
          # If the ‘attach’ request was used to connect to the debuggee, ‘disconnect’ does not terminate the debuggee.
          # This behavior can be controlled with the ‘terminateDebuggee’ argument (if supported by the debug adapter).

        when 'continue'
          # The request starts the debuggee to run again.
        when 'next'
          # The request starts the debuggee to run again for one step.
          # The debug adapter first sends the response and then a ‘stopped’ event (with reason ‘step’) after the step has completed.
        when 'pause'
          # The request suspends the debuggee.
          # The debug adapter first sends the response and then a ‘stopped’ event (with reason ‘pause’) after the thread has been paused successfully.
        when 'stepIn'
          # The request starts the debuggee to step into a function/method if possible.
          # If it cannot step into a target, ‘stepIn’ behaves like ‘next’.
          # The debug adapter first sends the response and then a ‘stopped’ event (with reason ‘step’) after the step has completed.
          # If there are multiple function/method calls (or other targets) on the source line,
          # the optional argument ‘targetId’ can be used to control into which target the ‘stepIn’ should occur.
          # The list of possible targets for a given source line can be retrieved via the ‘stepInTargets’ request.
        when 'stepOut'
          # The request starts the debuggee to run again for one step.
          # The debug adapter first sends the response and then a ‘stopped’ event (with reason ‘step’) after the step has completed.

        when 'setBreakpoints'
          # Sets multiple breakpoints for a single source and clears all previous breakpoints in that source.
          # To clear all breakpoint for a source, specify an empty array.
          # When a breakpoint is hit, a ‘stopped’ event (with reason ‘breakpoint’) is generated.

        when 'evaluate'
          # Evaluates the given expression in the context of the top most stack frame.
          # The expression has access to any variables and arguments that are in scope.
        when 'scopes'
          # The request returns the variable scopes for a given stackframe ID.
        when 'threads'
          # The request retrieves a list of all threads.
        when 'stackTrace'
          # The request returns a stacktrace from the current execution state.
        when 'variables'
          # Retrieves all child variables for the given variable reference.
          # An optional filter can be used to limit the fetched children to either named or indexed children

        when 'source'
          # The request retrieves the source code for a given source reference.

        else
          response[:success] = false
          response[:message] = 'Invalid command'
        end

        ::DAP::Response.new response
      end
    end
  end
end
