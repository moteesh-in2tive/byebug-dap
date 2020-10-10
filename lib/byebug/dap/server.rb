module Byebug
  module DAP
    class Server
      def initialize(capture: true, forward: true)
        @@main_process ||= Process.pid
        @started = false
        @mu = Mutex.new
        @cond = ConditionVariable.new
        @configured = false
        @capture = capture
        @forward = forward
      end

      def start(host, port = 0)
        case host
        when :stdio
          start_stdio
        when :unix
          start_unix port
        else
          start_tcp host, port
        end
      end

      def start_tcp(host, port)
        return if @started
        @started = true

        @ios = CapturedIO.new(@forward, @forward) if @capture
        launch_accept TCPServer.new(host, port)
      end

      def start_unix(socket)
        return if @started
        @started = true

        @ios = CapturedIO.new(@forward, @forward) if @capture
        launch_accept UNIXServer.new(socket)
      end

      def start_stdio
        return if @started
        @started = true

        stream = STDIO.new
        STDIN.close
        @ios = CapturedIO.new(false, @forward) if @capture
        launch stream
      end

      def wait_for_client
        @mu.synchronize do
          loop do
            return if @configured

            @cond.wait(@mu)
          end
        end
      end

      private

      def log
        if @ios
          @ios.log
        elsif defined?(LOG)
          LOG
        else
          STDERR
        end
      end

      def launch(stream)
        DebugThread.new do
          debug stream

        ensure
          @ios.restore
        end

        self
      end

      def launch_accept(server)
        DebugThread.new do
          while socket = server.accept
            debug socket
          end

        ensure
          @ios.restore
        end

        self
      end

      def debug(connection)
        session = Byebug::DAP::Session.new(connection, @ios) do
          @mu.synchronize do
            @configured = true
            @cond.broadcast
          end
        end

        session.execute

      rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Errno::ECONNABORTED
        log.puts "Client disconnected"

      rescue StandardError => e
        log.puts "#{e.message} (#{e.class})", *e.backtrace

      ensure
        session.stop!
      end
    end
  end
end
