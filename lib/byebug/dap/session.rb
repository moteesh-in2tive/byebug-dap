module Byebug
  module DAP
    class Session
      include SafeHelpers

      @@children = []

      def self.child_spawned(name, pid, socket)
        child = ChildSpawnedEventBody.new(name: name, pid: pid, socket: socket)
        @@children << child

        session = Context.interface
        session.event! child if session.is_a?(Byebug::DAP::Session)

        return true

      rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Errno::ECONNABORTED
        return false
      end

      def initialize(connection, ios, &block)
        @connection = connection
        @ios = ios
        @on_configured = block
        @pid = Process.pid
        @trace = TracePoint.new(:thread_begin, :thread_end) { |t| process_trace t }

        notify_of_children
      end

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

      def execute
        Context.interface = self
        Context.processor = Byebug::DAP::CommandProcessor

        Command.execute(self, receive) until @connection.closed?

        Context.interface = LocalInterface.new
      end

      def invalidate_handles!
        frame_ids.clear!
        variable_refs.clear!
      end

      def start!(mode)
        @trace.enable
        Byebug.mode = mode
        Byebug.start
        @exit_on_stop = true if mode == :launched
      end

      def configured!
        return unless @on_configured

        callback, @on_configured = @on_configured, callback
        callback.call
      end

      def stop!
        exit if @exit_on_stop && @pid == Process.pid

        Byebug.mode = :off
        Byebug.stop
        @trace.disable
        @connection.close
      end

      def event!(event, **values)
        if (cls = event.class.name.split('::').last) && cls.end_with?('EventBody')
          body, event = event, cls[0].downcase + cls[1...-9]

        elsif event.is_a?(String) && !values.empty?
          body = ::DAP.const_get("#{event[0].upcase}#{event[1..]}EventBody").new(values)
        end

        send ::DAP::Event.new(event: event, body: body)
      end

      def respond!(request, body = nil, success: true, message: 'Success', **values)
        send ::DAP::Response.new(
          request_seq: request.seq,
          command: request.command,
          success: success,
          message: message,
          body: body,
          **values)
      end

      def save_variables(*args)
        variable_refs << args
      end

      def restore_variables(ref)
        variable_refs[ref]
      end

      def save_frame(*args)
        frame_ids << args
      end

      def restore_frame(id)
        frame_ids[id]
      end

      private

      def notify_of_children
        @@children.each { |c| event! c }
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

      def frame_ids
        @frame_ids ||= Handles.new
      end

      def variable_refs
        @variable_refs ||= Handles.new
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
