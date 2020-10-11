module Byebug::DAP
  class CapturedIO
    def initialize(forward_stdout, forward_stderr)
      @forward_stdout = forward_stdout
      @forward_stderr = forward_stderr
      @stdout = CapturedOutput.new STDOUT
      @stderr = CapturedOutput.new STDERR
      @stop = false

      Byebug::DebugThread.new { capture }
    end

    def log
      if defined?(LOG)
        LOG
      elsif @stderr
        @stderr.original
      else
        STDERR
      end
    end

    def restore
      @stop = true
      @stdout.restore
      @stderr.restore
    end

    private

    def capture
      until @stop do
        r, = IO.select([@stdout.captured, @stderr.captured])

        r.each do |r|
          case r
          when @stdout.captured
            b = @stdout.captured.read_nonblock(1024)
            @stdout.original.write(b) if @forward_stdout
            send(:stdout, b)

          when @stderr.captured
            b = @stderr.captured.read_nonblock(1024)
            @stderr.original.write(b) if @forward_stderr
            send(:stderr, b)
          end
        end
      end

    rescue EOFError, Errno::EBADF
    rescue StandardError => e
      log.puts "#{e.message} (#{e.class})", *e.backtrace
    end

    def send(source, data)
      session = Byebug::Context.interface
      return unless session.is_a?(Session)

      session.event! 'output', category: source.to_s, output: data

    rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Errno::ECONNABORTED
      # client disconnected
    end
  end
end
