require 'socket'

class Byebug::Remote::Server
  def start_unix(path)
    return if @thread

    if wait_connection
      mutex = Mutex.new
      proceed = ConditionVariable.new
    end

    server = UNIXServer.new(path)

    yield if block_given?

    @thread = ::Byebug::DebugThread.new do
      while (session = server.accept)
        @main_loop.call(session)

        mutex.synchronize { proceed.signal } if wait_connection
      end
    end

    mutex.synchronize { proceed.wait(mutex) } if wait_connection
  end

  class STDIO
    extend Forwardable

    def initialize
      @in = STDIN
      @out = STDOUT
    end

    def close; @in.close; @out.close; end
    def flush; @in.flush; @out.flush; end
    def fsync; @in.fsync; @out.fsync; end

    def_delegators :@in, :close_read, :bytes, :chars, :codepoints, :each, :each_byte, :each_char, :each_codepoint, :each_line, :getbyte, :getc, :gets, :lines, :pread, :print, :printf, :read, :read_nonblock, :readbyte, :readchar, :readline, :readlines, :readpartial, :sysread, :ungetbyte, :ungetc
    def_delegators :@out, :<<, :close_write, :putc, :puts, :pwrite, :syswrite, :write, :write_nonblock
    public :<<, :bytes, :chars, :close_read, :close_write, :codepoints, :each, :each_byte, :each_char, :each_codepoint, :each_line, :getbyte, :getc, :gets, :lines, :pread, :print, :printf, :putc, :puts, :pwrite, :read, :read_nonblock, :readbyte, :readchar, :readline, :readlines, :readpartial, :sysread, :syswrite, :ungetbyte, :ungetc, :write, :write_nonblock
  end

  def start_stdio
    return if @thread

    if wait_connection
      mutex = Mutex.new
      proceed = ConditionVariable.new
    end

    yield if block_given?

    @thread = ::Byebug::DebugThread.new do
      @main_loop.call(STDIO.new)
    end
  end
end
