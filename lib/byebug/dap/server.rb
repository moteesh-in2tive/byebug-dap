module Byebug
  module DAP
    class Server
      def initialize(capture: true, forward: true)
        @@main_process ||= Process.pid
        @started = false
        @mu = Mutex.new
        @cond = ConditionVariable.new
        @configured = false
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

        launch TCPServer.new(host, port)
      end

      def start_unix(socket)
        return if @started
        @started = true

        launch UNIXServer.new(socket)
      end

      def start_stdio
        return if @started
        @started = true

        launch STDIO.new
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

      def launch(server)
        DebugThread.new do
          if server.respond_to?(:accept)
            while session = server.accept
              debug session
            end
          else
            debug server
          end
        end

        self
      end

      def debug(connection)
        session = Byebug::DAP::Session.new(connection) do
          @mu.synchronize do
            @configured = true
            @cond.broadcast
          end
        end

        session.execute

      rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Errno::ECONNABORTED
        STDERR.puts "Client disconnected"

      rescue StandardError => e
        STDERR.puts "#{e.message} (#{e.class})", *e.backtrace

      ensure
        session.stop!
      end
    end
  end
end
