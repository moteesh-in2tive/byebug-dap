module Byebug::DAP
  class CapturedOutput
    attr_reader :original, :captured

    def initialize(io)
      @io = io
      @original = io.dup
      @captured, pw = IO.pipe

      io.reopen(pw)
      pw.close
    end

    def restore
      @io.reopen(@original)
      @original.close
      @captured.close
      return nil
    end
  end
end
