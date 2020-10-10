module Byebug::DAP
  class STDIO
    extend Forwardable

    def initialize
      @in = STDIN.dup
      @out = STDOUT.dup
      @in.sync = true
      @out.sync = true
    end

    def close; @in.close; @out.close; end
    def flush; @in.flush; @out.flush; end
    def fsync; @in.fsync; @out.fsync; end
    def closed?; @in.closed? || @out.closed?; end

    def_delegators :@in, :close_read, :bytes, :chars, :codepoints, :each, :each_byte, :each_char, :each_codepoint, :each_line, :getbyte, :getc, :gets, :lines, :pread, :print, :printf, :read, :read_nonblock, :readbyte, :readchar, :readline, :readlines, :readpartial, :sysread, :ungetbyte, :ungetc
    def_delegators :@out, :<<, :close_write, :putc, :puts, :pwrite, :syswrite, :write, :write_nonblock
    public :<<, :bytes, :chars, :close_read, :close_write, :codepoints, :each, :each_byte, :each_char, :each_codepoint, :each_line, :getbyte, :getc, :gets, :lines, :pread, :print, :printf, :putc, :puts, :pwrite, :read, :read_nonblock, :readbyte, :readchar, :readline, :readlines, :readpartial, :sysread, :syswrite, :ungetbyte, :ungetc, :write, :write_nonblock
  end
end
