module Byebug
  module DAP
    # Byebug DAP Server
    class Server
      # Create a new server.
      # @param capture [Boolean] if `true`, the debugee's STDOUT and STDERR will be captured
      # @param forward [Boolean] if `false`, the debugee's STDOUT and STDERR will be supressed
      def initialize(capture: true, forward: true)
        @started = false
        @mu = Mutex.new
        @cond = ConditionVariable.new
        @configured = false
        @capture = capture
        @forward = forward
      end

      # Starts the server. Calls {#start_stdio} if `host == :stdio`. Calls
      # {#start_unix} with `port` if `host == :unix`. Calls {#start_tcp} with
      # `host` and `port` otherwise.
      # @param host `:stdio`, `:unix`, or the TCP host name
      # @param port the Unix socket path or TCP port
      # @return [Server]
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

      # Starts the server, listening on a TCP socket.
      # @param host [std:String] the IP to listen on
      # @param port [std:Number] the port to listen on
      # @return [Server]
      def start_tcp(host, port)
        return if @started
        @started = true

        @ios = CapturedIO.new(@forward, @forward) if @capture
        launch_accept TCPServer.new(host, port)
      end

      # Starts the server, listening on a Unix socket.
      # @param socket [std:String] the Unix socket path
      # @return [Server]
      def start_unix(socket)
        return if @started
        @started = true

        @ios = CapturedIO.new(@forward, @forward) if @capture
        launch_accept UNIXServer.new(socket)
      end

      # Starts the server using STDIN and STDOUT to communicate.
      # @return [Server]
      def start_stdio
        return if @started
        @started = true

        stream = STDIO.new
        STDIN.close
        @ios = CapturedIO.new(false, @forward) if @capture
        launch stream
      end

      # Blocks until a client connects and begins debugging.
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
          @ios&.restore
        end

        self
      end

      def launch_accept(server)
        DebugThread.new do
          while socket = server.accept
            debug socket
          end

        ensure
          @ios&.restore
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
