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
        invalidate_handles!
        @proceed = true
      end

      def at_line
        puts "at line"

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
        puts "at end"

        process_commands
      end

      def process_commands
        @proceed = false

        until @proceed
          run_cmd interface.gets
        end

      rescue EOFError
        proceed!
        Byebug.mode = :off
        Byebug.stop
        return
      end

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

      def invalidate_handles!
        interface.stack_frames.clear!
        interface.variable_scopes.clear!
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

          send_event 'stopped', reason: 'step'

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

          send_event 'stopped', reason: 'step'

        when 'stepOut'
          # "The request starts the debuggee to run again for one step.
          # "The debug adapter first sends the response and then a ‘stopped’ event (with reason ‘step’) after the step has completed.

          respond request

          # TODO threads
          context.step_out(context.frame.pos + 1, false)
          context.frame = 0
          proceed!

          send_event 'stopped', reason: 'step'

        when 'setBreakpoints'
          # "Sets multiple breakpoints for a single source and clears all previous breakpoints in that source.
          # "To clear all breakpoint for a source, specify an empty array.
          # "When a breakpoint is hit, a ‘stopped’ event (with reason ‘breakpoint’) is generated.

        when 'evaluate'
          # "Evaluates the given expression in the context of the top most stack frame.
          # "The expression has access to any variables and arguments that are in scope.

        when 'scopes'
          # "The request returns the variable scopes for a given stackframe ID.

        when 'threads'
          # "The request retrieves a list of all threads.

          threads = Byebug
            .contexts
            # .sort_by(&:thnum)
            .map { |ctx| ::DAP::Thread.new(
              id: ctx.thnum,
              name: ctx.thread.name || "Thread ##{ctx.thnum}" )}

          respond request,
            body: ::DAP::ThreadsResponseBody.new(threads: threads)

        when 'stackTrace'
          # "The request returns a stacktrace from the current execution state.

          ctx = Byebug.contexts.find { |c| c.thnum == request.arguments.threadId }

          if ctx.stack_size > 0xFFFF
            respond request, success: false, message: "Thread stack size exceeds 2^16"
            return
          end

          first = request.arguments.startFrame || 0
          if !request.arguments.levels
            last = ctx.stack_size
          else
            last = first + request.arguments.levels
            if last > ctx.stack_size
              last = ctx.stack_size
            end
          end

          frames = (first...last).map do |i|
            frame = ::Byebug::Frame.new(ctx, i)
            ::DAP::StackFrame.new(
              id: interface.stack_frames << [ctx.thnum, i],
              name: frame.deco_call,
              source: ::DAP::Source.new(
                name: File.basename(frame.file),
                path: File.expand_path(frame.file)),
              line: frame.line)
          end

          respond request,
            body: ::DAP::StackTraceResponseBody.new(
              stackFrames: frames,
              totalFrames: ctx.stack_size)

        when 'variables'
          # "Retrieves all child variables for the given variable reference.
          # "An optional filter can be used to limit the fetched children to either named or indexed children

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

        else
          respond request,
            succcess: false,
            message: 'Invalid command'
        end
      end
    end
  end
end
