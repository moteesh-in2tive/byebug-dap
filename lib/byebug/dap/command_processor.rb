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
        interface.invalidate_handles!
        @proceed = true
      end

      def stopped
        reason, value = @stop_reason
        case reason
        when :breakpoint
          number = Byebug.breakpoints.index(value) + 1

          send_event 'stopped',
            reason: 'breakpoint',
            description: 'Hit breakpoint',
            threadId: context.thnum,
            text: "Stopped by breakpoint #{number} at #{frame.file}:#{frame.line}"

        else
          send_event 'stopped', reason: 'step', text: "Stopped at #{frame.file}:#{frame.line}"
        end

        @stop_reason = nil

        process_commands
      end

      alias at_line stopped

      def at_end
        @stop_reason = [:ended]
        stopped
      end

      def at_return(return_value)
        @stop_reason = [:returned, return_value]
        stopped
      end

      # def at_tracing
      #   interface.puts "Tracing: #{context.full_location}"

      #   # run_auto_cmds(2)
      # end

      # def at_catchpoint(exception)
      #   interface.puts "Catchpoint at #{context.location}: `#{exception}'"
      # end

      def at_breakpoint(brkpt)
        @stop_reason = [:breakpoint, brkpt]
      end

      def process_commands
        @proceed = false

        until @proceed
          begin
            run_cmd interface.gets
          rescue IOError, SystemCallError
            raise
          rescue StandardError => e
            puts "\n! #{e.message} (#{e.class})", *e.backtrace
          end
        end

      rescue EOFError
        proceed!
        Byebug.mode = :off
        Byebug.stop
        return
      end

      # def safe_inspect(var)
      #   var.inspect
      # rescue StandardError
      #   safe_to_s(var)
      # end

      # def safe_to_s(var)
      #   var.to_s
      # rescue StandardError
      #   "*Error in evaluation*"
      # end

      def respond(request, body = {}, success: true, **values)
        interface.puts(::DAP::Response.new(
          request_seq: request.seq,
          command: request.command,
          success: success,
          body: body,
          **values))
      end

      def send_event(event, **values)
        body = ::DAP.const_get("#{event[0].upcase}#{event[1..]}EventBody").new(values) unless values.empty?
        interface.puts(::DAP::Event.new(event: event, body: body))
      end

      def run_cmd(request)
        case request.command
        when 'initialize'
          respond request # we support nothing

          send_event 'initialized'

        when 'attach'
          # "The attach request is sent from the client to the debug adapter to attach to a debuggee that is already running.

          # TODO what do we attach?
          respond request

        when 'launch'
          # "This launch request is sent from the client to the debug adapter to start the debuggee with or without debugging (if ‘noDebug’ is true).

          # TODO how do we launch?
          respond request,
            succcess: false,
            message: 'Launching not supported'

        when 'pause'
          # "The request suspends the debuggee.
          # "The debug adapter first sends the response and then a ‘stopped’ event (with reason ‘pause’) after the thread has been paused successfully.

          # TODO threads
          respond request

          Byebug.start
          Byebug.thread_context(Thread.main).interrupt

          send_event 'stopped', reason: 'pause'

        when 'continue', 'disconnect'
          # Disconnect
          # "The ‘disconnect’ request is sent from the client to the debug adapter in order to stop debugging.
          # "It asks the debug adapter to disconnect from the debuggee and to terminate the debug adapter.
          # "If the debuggee has been started with the ‘launch’ request, the ‘disconnect’ request terminates the debuggee.
          # "If the ‘attach’ request was used to connect to the debuggee, ‘disconnect’ does not terminate the debuggee.
          # "This behavior can be controlled with the ‘terminateDebuggee’ argument (if supported by the debug adapter).

          # Continue
          # "The request starts the debuggee to run again.

          proceed!

          Byebug.mode = :off
          Byebug.stop
          respond request

        when 'next'
          # "The request starts the debuggee to run again for one step.
          # "The debug adapter first sends the response and then a ‘stopped’ event (with reason ‘step’) after the step has completed.

          respond request

          # TODO threads
          context.step_over(1, context.frame.pos)
          proceed!

        when 'stepIn'
          # "The request starts the debuggee to step into a function/method if possible.
          # "If it cannot step into a target, ‘stepIn’ behaves like ‘next’.
          # "The debug adapter first sends the response and then a ‘stopped’ event (with reason ‘step’) after the step has completed.
          # "If there are multiple function/method calls (or other targets) on the source line,
          # "the optional argument ‘targetId’ can be used to control into which target the ‘stepIn’ should occur.
          # "The list of possible targets for a given source line can be retrieved via the ‘stepInTargets’ request.

          respond request

          # TODO threads
          context.step_into(1, context.frame.pos)
          proceed!

        when 'stepOut'
          # "The request starts the debuggee to run again for one step.
          # "The debug adapter first sends the response and then a ‘stopped’ event (with reason ‘step’) after the step has completed.

          respond request

          # TODO threads
          context.step_out(context.frame.pos + 1, false)
          context.frame = 0
          proceed!

        when 'evaluate'
          # "Evaluates the given expression in the context of the top most stack frame.
          # "The expression has access to any variables and arguments that are in scope.

          body = interface.evaluate(request.arguments.frameId, request.arguments.expression) { |err, v| handle_error(request, err, v, 'frame id'); return }

          respond request, body: body

        when 'scopes'
          # "The request returns the variable scopes for a given stackframe ID.

          scopes = interface.scopes(request.arguments.frameId) { |err, v| handle_error(request, err, v, 'frame id'); return }

          respond request, body: ::DAP::ScopesResponseBody.new(scopes: scopes)

        when 'threads'
          # "The request retrieves a list of all threads.

          respond request, body: ::DAP::ThreadsResponseBody.new(threads: interface.threads)

        when 'stackTrace'
          # "The request returns a stacktrace from the current execution state.

          frames, stack_size = interface.frames(
            request.arguments.threadId,
            at: request.arguments.startFrame,
            count: request.arguments.levels,
          ) { |err, v| handle_error(request, err, v); return }

          respond request,
            body: ::DAP::StackTraceResponseBody.new(
              stackFrames: frames,
              totalFrames: stack_size)

        when 'variables'
          # "Retrieves all child variables for the given variable reference.
          # "An optional filter can be used to limit the fetched children to either named or indexed children

          variables = interface.variables(
            request.arguments.variablesReference,
            at: request.arguments.start,
            count: request.arguments.count,
            filter: request.arguments.filter,
          ) { |err, v| handle_error(request, err, v, 'variable reference'); return }

          respond request, body: ::DAP::VariablesResponseBody.new(variables: variables)

        when 'source'
          # "The request retrieves the source code for a given source reference.

          path = request.arguments.source.path
          if File.readable?(path)
            respond request, body: ::DAP::SourceResponseBody.new(content: IO.read(path))

          elsif File.exist?(path)
            respond request, success: false, message: "Source file '#{path}' exists but cannot be read"

          else
            respond request, success: false, message: "No source file available for '#{path}'"
          end

        when 'setBreakpoints'
          # "Sets multiple breakpoints for a single source and clears all previous breakpoints in that source.
          # "To clear all breakpoint for a source, specify an empty array.
          # "When a breakpoint is hit, a ‘stopped’ event (with reason ‘breakpoint’) is generated.

          path = File.realpath(request.arguments.source.path)
          ::Byebug.breakpoints.each { |bp| ::Byebug::Breakpoint.remove(bp.id) if bp.source == path }

          lines = ::Byebug::Breakpoint.potential_lines(path)
          verified = []
          request.arguments.breakpoints.each do |requested|
            next unless lines.include? requested.line

            bp = ::Byebug::Breakpoint.add(path, requested.line)
            verified << ::DAP::Breakpoint.new(
              id: bp.id,
              verified: true,
              line: requested.line)
          end

          respond request, body: ::DAP::SetBreakpointsResponseBody.new(breakpoints: verified)

        else
          respond request,
            succcess: false,
            message: 'Invalid command'
        end
      end

      private

      def handle_error(request, err, v, entry = 'entry')
        case err
        when :missing_argument
          respond request, success: false, message: "Missing #{v}"

        when :missing_entry
          respond request, success: false, message: "Invalid #{entry} #{v}"

        when :missing_thread
          respond request, success: false, message: "Cannot locate thread ##{v}"

        when :missing_frame
          respond request, success: false, message: "Cannot locate frame ##{v}"

        when :invalid_entry
          respond request, success: false, message: "Error resolving #{entry}: #{v}"

        else
          raise "Unknown internal error: #{err}"
        end
      end
    end
  end
end
