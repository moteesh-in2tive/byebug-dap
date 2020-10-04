module Byebug
  module DAP
    class Controller
      class DisconnectError < StandardError; end

      def initialize(interface)
        @interface = interface
      end

      def process_commands
        loop do
          @request = @interface.receive
          execute_command @request

        rescue InvalidRequestArgumentError => e
          handle_error e
        end

      rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Errno::ECONNABORTED, DisconnectError
        STDERR.puts "\nClient disconnected"

      rescue StandardError => e
        STDERR.puts "\n! #{e.message} (#{e.class})", *e.backtrace

      ensure
        Byebug.mode = :off
        Byebug.stop
        @interface.socket.close
      end

      def find_processor(threadId)
        ctx = @interface.find_thread(threadId)
        ctx.__send__(:processor)
      end

      def running!
        raise InvalidRequestArgumentError.new(:not_running, nil) unless Byebug.started?
      end

      def execute_command(request)
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

        when 'disconnect'
          # "The ‘disconnect’ request is sent from the client to the debug adapter in order to stop debugging.
          # "It asks the debug adapter to disconnect from the debuggee and to terminate the debug adapter.
          # "If the debuggee has been started with the ‘launch’ request, the ‘disconnect’ request terminates the debuggee.
          # "If the ‘attach’ request was used to connect to the debuggee, ‘disconnect’ does not terminate the debuggee.
          # "This behavior can be controlled with the ‘terminateDebuggee’ argument (if supported by the debug adapter).

          respond!
          raise DisconnectError

        when 'attach'
          # "The attach request is sent from the client to the debug adapter to attach to a debuggee that is already running.

          Byebug.mode = :attached
          Byebug.start
          respond!

        when 'launch'
          # "This launch request is sent from the client to the debug adapter to start the debuggee with or without debugging (if ‘noDebug’ is true).

          unless request.arguments.noDebug
            Byebug.mode = :launched
            Byebug.start
          end

          respond!

        when 'configurationDone'
          # "This optional request indicates that the client has finished initialization of the debug adapter.

          respond!

        when 'pause'
          running!

          ctx = @interface.find_thread(request.arguments.threadId)
          ctx.interrupt
          ctx.__send__(:processor) << request

        when 'next', 'stepIn', 'stepOut', 'continue'
          running!

          find_processor(request.arguments.threadId) << request
          respond!

        when 'evaluate'
          # "Evaluates the given expression in the context of the top most stack frame.
          # "The expression has access to any variables and arguments that are in scope.

          running!
          respond! body: @interface.evaluate(request.arguments.frameId, request.arguments.expression)

        when 'scopes'
          # "The request returns the variable scopes for a given stackframe ID.

          running!
          respond! body: ::DAP::ScopesResponseBody.new(
            scopes: @interface.scopes(request.arguments.frameId))

        when 'threads'
          # "The request retrieves a list of all threads.

          running!
          respond! body: ::DAP::ThreadsResponseBody.new(threads: @interface.threads)

        when 'stackTrace'
          # "The request returns a stacktrace from the current execution state.

          running!

          frames, stack_size = @interface.frames(
            request.arguments.threadId,
            at: request.arguments.startFrame,
            count: request.arguments.levels)

          respond! body: ::DAP::StackTraceResponseBody.new(
            stackFrames: frames,
            totalFrames: stack_size)

        when 'variables'
          # "Retrieves all child variables for the given variable reference.
          # "An optional filter can be used to limit the fetched children to either named or indexed children

          running!

          variables = @interface.variables(
            request.arguments.variablesReference,
            at: request.arguments.start,
            count: request.arguments.count,
            filter: request.arguments.filter)

          respond! body: ::DAP::VariablesResponseBody.new(variables: variables)

        when 'source'
          # "The request retrieves the source code for a given source reference.

          running!

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

          running!

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

      def handle_error(ex)
        case ex.error
        when :not_running
          respond! @request, success: false, message: "Debugger is not running"

        when :missing_argument
          respond! @request, success: false, message: "Missing #{ex.scope}"

        when :missing_entry
          respond! @request, success: false, message: "Invalid #{ex.scope} #{ex.value}"

        when :missing_thread
          respond! @request, success: false, message: "Cannot locate thread ##{ex.value}"

        when :missing_frame
          respond! @request, success: false, message: "Cannot locate frame ##{ex.value}"

        when :invalid_entry
          respond! @request, success: false, message: "Error resolving #{ex.scope}: #{ex.value}"

        else
          raise "Unknown internal error: #{err}"
        end
      end
    end
  end
end
