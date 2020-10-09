module Byebug
  module DAP
    class Controller
      def initialize(interface, signal_start = nil)
        @interface = interface
        @signal_start = signal_start

        @trace = TracePoint.new(:thread_begin, :thread_end) { |t| process_trace t }
      end

      def run
        loop do
          @request = @interface.receive
          result = process_command @request
          return if result == :stop
        end

      rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Errno::ECONNABORTED
        STDERR.puts "\nClient disconnected"

      ensure
        exit if @exit_on_disconnect

        Byebug.mode = :off
        Byebug.stop
        @interface.socket.close
        @trace.disable
      end

      private

      def process_trace(trace)
        return unless Byebug.started?

        ctx = Byebug.contexts.find { |c| c.thread == Thread.current }

        case trace.event
        when :thread_begin
          @interface.event! 'thread', reason: 'started', threadId: ctx.thnum
        when :thread_end
          @interface.event! 'thread', reason: 'exited', threadId: ctx.thnum
        end

      rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Errno::ECONNABORTED
        # client disconnected, ignore error
      end

      def process_command(request)
        case request.command
        when 'attach', 'launch'
          if Byebug.started?
            respond! success: false, message: "Cannot #{request.command} - debugger is already running"
            return
          end
        when 'pause', 'next', 'stepIn', 'stepOut', 'continue', 'evaluate', 'variables', 'scopes', 'threads', 'stackTrace'
          unless Byebug.started?
            respond! success: false, message: "Cannot #{request.command} - debugger is not running"
            return
          end
        end

        case request.command
        when 'initialize'
          # "The ‘initialize’ request is sent as the first request from the client to the debug adapter
          # "in order to configure it with client capabilities and to retrieve capabilities from the debug adapter.
          # "Until the debug adapter has responded to with an ‘initialize’ response, the client must not send any additional requests or events to the debug adapter.
          # "In addition the debug adapter is not allowed to send any requests or events to the client until it has responded with an ‘initialize’ response.
          # "The ‘initialize’ request may only be sent once.

          respond! body: ::DAP::Capabilities.new(
            supportsConfigurationDoneRequest: true)

          @interface.event! 'initialized'
          return

        when 'disconnect'
          # "The ‘disconnect’ request is sent from the client to the debug adapter in order to stop debugging.
          # "It asks the debug adapter to disconnect from the debuggee and to terminate the debug adapter.
          # "If the debuggee has been started with the ‘launch’ request, the ‘disconnect’ request terminates the debuggee.
          # "If the ‘attach’ request was used to connect to the debuggee, ‘disconnect’ does not terminate the debuggee.
          # "This behavior can be controlled with the ‘terminateDebuggee’ argument (if supported by the debug adapter).

          respond!
          return :stop

        when 'attach'
          # "The attach request is sent from the client to the debug adapter to attach to a debuggee that is already running.

          Byebug.mode = :attached
          Byebug.start
          @trace.enable

          @signal_start.call(:attach) if @signal_start

          respond!
          return

        when 'launch'
          # "This launch request is sent from the client to the debug adapter to start the debuggee with or without debugging (if ‘noDebug’ is true).

          unless request.arguments.noDebug
            Byebug.mode = :launched
            Byebug.start
            @trace.enable
          end

          @exit_on_disconnect = true
          @signal_start.call(:launch) if @signal_start

          respond!
          return

        when 'configurationDone'
          # "This optional request indicates that the client has finished initialization of the debug adapter.

          respond!
          return

        when 'pause', 'next', 'stepIn', 'stepOut', 'continue'
          ctx = @interface.find_thread(request.arguments.threadId)
          ctx.interrupt if request.command == 'pause'

          ctx.__send__(:processor) << request
          respond!

        when 'evaluate'
          # "Evaluates the given expression in the context of the top most stack frame.
          # "The expression has access to any variables and arguments that are in scope.

          respond! body: @interface.evaluate(request.arguments.frameId, request.arguments.expression)

        when 'variables'
          # "Retrieves all child variables for the given variable reference.
          # "An optional filter can be used to limit the fetched children to either named or indexed children

          variables = @interface.variables(
            request.arguments.variablesReference,
            at: request.arguments.start,
            count: request.arguments.count,
            filter: request.arguments.filter)

          respond! body: ::DAP::VariablesResponseBody.new(variables: variables)

        when 'scopes'
          # "The request returns the variable scopes for a given stackframe ID.

          respond! body: ::DAP::ScopesResponseBody.new(
            scopes: @interface.scopes(request.arguments.frameId))

        when 'threads'
          # "The request retrieves a list of all threads.

          respond! body: ::DAP::ThreadsResponseBody.new(threads: @interface.threads)

        when 'stackTrace'
          # "The request returns a stacktrace from the current execution state.

          frames, stack_size = @interface.frames(
            request.arguments.threadId,
            at: request.arguments.startFrame,
            count: request.arguments.levels)

          respond! body: ::DAP::StackTraceResponseBody.new(
            stackFrames: frames,
            totalFrames: stack_size)

        when 'source'
          # "The request retrieves the source code for a given source reference.

          path = request.arguments.source.path
          if File.readable?(path)
            respond! body: ::DAP::SourceResponseBody.new(content: IO.read(path))

          elsif File.exist?(path)
            respond! success: false, message: "Source file '#{path}' exists but cannot be read"

          else
            respond! success: false, message: "No source file available for '#{path}'"
          end

        when 'setBreakpoints'
          # "Sets multiple breakpoints for a single source and clears all previous breakpoints in that source.
          # "To clear all breakpoint for a source, specify an empty array.
          # "When a breakpoint is hit, a ‘stopped’ event (with reason ‘breakpoint’) is generated.

          unless File.exist?(request.arguments.source.path)
            # file doesn't exist, no breakpoints set
            respond! body: ::DAP::SetBreakpointsResponseBody.new(breakpoints: [])
            return
          end

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

          respond! body: ::DAP::SetBreakpointsResponseBody.new(breakpoints: verified)

        else
          respond! success: false, message: 'Invalid command'
        end

      rescue InvalidRequestArgumentError => e
        case e.error
        when :missing_argument
          respond! success: false, message: "Missing #{e.scope}"

        when :missing_entry
          respond! success: false, message: "Invalid #{e.scope} #{e.value}"

        when :missing_thread
          respond! success: false, message: "Cannot locate thread ##{e.value}"

        when :missing_frame
          respond! success: false, message: "Cannot locate frame ##{e.value}"

        when :invalid_entry
          respond! success: false, message: "Error resolving #{e.scope}: #{e.value}"

        else
          respond! success: false, message: "An internal error occured"
          STDERR.puts "#{e.message} (#{e.class})", *e.backtrace
        end

      rescue CommandProcessor::TimeoutError => e
        respond! success: false, message: "Debugger on thread ##{e.context.thnum} is not responding"

      rescue StandardError => e
        respond! success: false, message: "An internal error occured"
        STDERR.puts "#{e.message} (#{e.class})", *e.backtrace
      end

      def respond!(body = {}, success: true, message: 'Success', **values)
        # TODO make body default to nil?
        @interface << ::DAP::Response.new(
          request_seq: @request.seq,
          command: @request.command,
          success: success,
          message: message,
          body: body,
          **values)
      end
    end
  end
end
