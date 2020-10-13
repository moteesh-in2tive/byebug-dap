module Byebug
  module DAP
    # A Byebug DAP session
    class Session
      include SafeHelpers

      # Call {Session#stop!} on {Byebug::Context.interface} if it is a {Session}.
      # @return [Boolean] whether {Byebug::Context.interface} was a {Session}
      def self.stop!
        session = Byebug::Context.interface
        return false unless session.is_a?(Session)

        session.stop!
        true
      end

      # Add a {ChildSpawnedEventBody} entry and send a `childSpawned` event to
      # the current session's client, if {Byebug::Context.interface} is a
      # {Session}.
      def self.child_spawned(name, pid, socket)
        child = ChildSpawnedEventBody.new(name: name, pid: pid, socket: socket)
        (@@children ||= []) << child

        session = Context.interface
        return false unless session.is_a?(Session)

        session.event! child
        return true

      rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Errno::ECONNABORTED
        return false
      end

      # Create a new session instance.
      # @param connection [IO] the connection to the client
      # @param ios [CapturedIO] the captured IO
      # @yield called once the client is done configuring the session (optional)
      def initialize(connection, ios = nil, &block)
        @connection = connection
        @ios = ios
        @on_configured = block
        @pid = Process.pid
        @log_points = {}
        @frame_ids = Handles.new
        @variable_refs = Handles.new
        @trace = TracePoint.new(:thread_begin, :thread_end) { |t| process_trace t }

        notify_of_children
      end

      # Write a message to the log.
      def log(*args)
        logger =
          if @ios
            @ios.log
          elsif defined?(LOG)
            LOG
          else
            STDERR
          end
        logger.puts(*args)
      end

      # Execute requests from the client until the connection is closed.
      def execute
        Context.interface = self
        Context.processor = Byebug::DAP::CommandProcessor

        Command.execute(self, receive) until @connection.closed?

        Context.interface = LocalInterface.new
      end

      # Invalidate frame IDs and variables references.
      # @note This should only be used by a {ContextualCommand} that un-pauses its context
      # @api private
      def invalidate_handles!
        @frame_ids.clear!
        @variable_refs.clear!
      end

      # Start Byebug.
      # @param mode [Symbol] `:attached` or `:launched`
      # @note This should only be used by {Command::Attach} or {Command::Launch}
      # @api private
      def start!(mode)
        @trace.enable
        Byebug.mode = mode
        Byebug.start
        @exit_on_stop = true if mode == :launched
      end

      # Call the block passed to {#initialize}.
      # @note This should only be used by {Command::ConfigurationDone}
      # @api private
      def configured!
        return unless @on_configured

        callback, @on_configured = @on_configured, callback
        callback.call
      end

      # Stop Byebug and close the client's connection.
      # @note If the session was started with the `launch` command, this will call {Kernel#exit}
      def stop!
        exit if @exit_on_stop && @pid == Process.pid

        Byebug.mode = :off
        Byebug.stop
        @trace.disable
        @connection.close
      end

      # Send an event to the client. Either call with an event name and body
      # attributes, or call with an already constructed body.
      # @param event [String|Protocol::Base] the event name or event body
      # @param values [Hash] event body attributes
      def event!(event, **values)
        if (cls = event.class.name.split('::').last) && cls.end_with?('EventBody')
          body, event = event, cls[0].downcase + cls[1...-9]

        elsif event.is_a?(String) && !values.empty?
          body = ::DAP.const_get("#{event[0].upcase}#{event[1..]}EventBody").new(values)
        end

        send ::DAP::Event.new(event: event, body: body)
      end

      # Send a response to the client.
      # @param request [Protocol::Request] the request to respond to
      # @param body [Hash|Protocol::Base] the response body
      # @param success [Boolean] whether the request was successful
      # @param message [String] the response message
      # @param values [Hash] additional response attributes
      def respond!(request, body = nil, success: true, message: 'Success', **values)
        send ::DAP::Response.new(
          request_seq: request.seq,
          command: request.command,
          success: success,
          message: message,
          body: body,
          **values)
      end

      # Create a variables reference.
      def save_variables(*args)
        @variable_refs << args
      end

      # Retrieve variables from a reference.
      def restore_variables(ref)
        @variable_refs[ref]
      end

      # Create a frame ID.
      def save_frame(*args)
        @frame_ids << args
      end

      # Restore a frame from an ID.
      def restore_frame(id)
        @frame_ids[id]
      end

      # Get the log point expression associated with `breakpoint`.
      # @param breakpoint [Byebug::Breakpoint] the breakpoint
      # @return [String] the log point expression
      # @note This should only be used by {CommandProcessor}
      # @api private
      def get_log_point(breakpoint)
        @log_points[breakpoint.id]
      end

      # Associate a log point expression with `breakpoint`.
      # @param breakpoint [Byebug::Breakpoint] the breakpoint
      # @param expr [String] the log point expression
      # @note This should only be used by {CommandProcessor}
      # @api private
      def set_log_point(breakpoint, expr)
        if expr.nil? || expr.empty?
          @log_points.delete(breakpoint.id)
        else
          @log_points[breakpoint.id] = expr
        end
      end

      # Delete the specified breakpoints and any log points associated with
      # them.
      # @param breakpoints [Array<Byebug::Breakpoint>] the breakpoints
      def clear_breakpoints(*breakpoints)
        breakpoints.each do |breakpoint|
          Byebug.breakpoints.delete(breakpoint)
          @log_points.delete(breakpoint.id)
        end
      end

      private

      def notify_of_children
        @@children.each { |c| event! c } if defined?(@@children)
      rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Errno::ECONNABORTED
        # client is closed
      end

      def send(message)
        log "#{Process.pid} > #{message.to_wire}" if Debug.protocol
        message.validate!
        @connection.write ::DAP::Encoding.encode(message)
      end

      def receive
        m = ::DAP::Encoding.decode(@connection)
        log "#{Process.pid} < #{m.to_wire}" if Debug.protocol
        m
      end

      def process_trace(trace)
        return unless Byebug.started?

        ctx = Byebug.contexts.find { |c| c.thread == Thread.current }

        case trace.event
        when :thread_begin
          event! 'thread', reason: 'started', threadId: ctx.thnum
        when :thread_end
          event! 'thread', reason: 'exited', threadId: ctx.thnum
        end

      rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Errno::ECONNABORTED
        # client disconnected, ignore error
      end
    end
  end
end
