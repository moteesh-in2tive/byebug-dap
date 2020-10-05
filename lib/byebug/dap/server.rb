module Byebug
  module DAP
    class Server
      class STDIO
        extend Forwardable

        def initialize
          @in = STDIN
          @out = STDOUT
          STDIN.sync = true
          STDOUT.sync = true
        end

        def close; @in.close; @out.close; end
        def flush; @in.flush; @out.flush; end
        def fsync; @in.fsync; @out.fsync; end

        def_delegators :@in, :close_read, :bytes, :chars, :codepoints, :each, :each_byte, :each_char, :each_codepoint, :each_line, :getbyte, :getc, :gets, :lines, :pread, :print, :printf, :read, :read_nonblock, :readbyte, :readchar, :readline, :readlines, :readpartial, :sysread, :ungetbyte, :ungetc
        def_delegators :@out, :<<, :close_write, :putc, :puts, :pwrite, :syswrite, :write, :write_nonblock
        public :<<, :bytes, :chars, :close_read, :close_write, :codepoints, :each, :each_byte, :each_char, :each_codepoint, :each_line, :getbyte, :getc, :gets, :lines, :pread, :print, :printf, :putc, :puts, :pwrite, :read, :read_nonblock, :readbyte, :readchar, :readline, :readlines, :readpartial, :sysread, :syswrite, :ungetbyte, :ungetc, :write, :write_nonblock
      end

      def initialize(&block)
        @started = false
        if block_given?
          @on_start = block
          @mu = Mutex.new
          @cond = ConditionVariable.new
        end
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

        return unless defined?(@on_start)

        @mu.synchronize { @cond.wait(@mu) }

        @on_start.call
      end

      def debug(session)
        Context.interface = Byebug::DAP::Interface.new(session)
        Context.processor = Byebug::DAP::CommandProcessor

        signal_start = ->(_) { @mu.synchronize { @cond.signal } } if defined?(@on_start)
        Byebug::DAP::Controller.new(Context.interface, signal_start).run
      end
    end
  end
end
