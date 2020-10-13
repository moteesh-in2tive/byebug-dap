module Byebug::DAP
  # Captures STDOUT and STDERR. See {CapturedOutput}.
  # @api private
  class CapturedIO
    # Capture STDOUT and STDERR and create a new {Byebug::DebugThread} running
    # {#capture}. See {CapturedOutput#initialize}.
    # @param forward_stdout [Boolean] if true, captured STDOUT is forwarded to the original STDOUT.
    # @param forward_stderr [Boolean] if true, captured STDERR is forwarded to the original STDERR.
    def initialize(forward_stdout, forward_stderr)
      @forward_stdout = forward_stdout
      @forward_stderr = forward_stderr
      @stdout = CapturedOutput.new STDOUT
      @stderr = CapturedOutput.new STDERR
      @stop = false

      Byebug::DebugThread.new { capture }
    end

    # Return an IO that can be used for logging.
    # @return [IO]
    def log
      if defined?(LOG)
        LOG
      elsif @stderr
        @stderr.original
      else
        STDERR
      end
    end

    # Restore the original STDOUT and STDERR. See {CapturedOutput#restore}.
    def restore
      @stop = true
      @stdout.restore
      @stderr.restore
    end

    private

    # In a loop, read from the captured STDOUT and STDERR and send an output
    # event to the active session's client (if there is an active session), and
    # optionally forward the output to the original STDOUT/STDERR.
    # @api private
    # @!visibility public
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
