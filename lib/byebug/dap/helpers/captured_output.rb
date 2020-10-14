module Byebug::DAP
  # Captures an IO output stream.
  # @api private
  class CapturedOutput
    # The original stream, {std:IO#dup duplicated} from `io`. Writing to this IO
    # will write to the original file.
    # @return [std:IO]
    attr_reader :original

    # The captured stream. Captured output can be read from this IO.
    # @return [std:IO]
    attr_reader :captured

    # Capture `io`, {std:IO#dup duplicate} the original, open an {std:IO.pipe
    # pipe} pair, and {std:IO#reopen reopen} `io` to redirect it to the pipe.
    def initialize(io)
      @io = io
      @original = io.dup
      @captured, pw = IO.pipe

      io.reopen(pw)
      pw.close
    end

    # Restore `io` to the original file.
    def restore
      @io.reopen(@original)
      @original.close
      @captured.close
      return nil
    end
  end
end
