module Byebug::DAP
  class Command::StackTrace < Command
    # "The request returns a stacktrace from the current execution state.

    register!

    def execute
      started!

      ctx = find_thread(args.threadId)

      first = args.startFrame || 0
      if !args.levels
        last = ctx.stack_size
      else
        last = first + args.levels
        if last > ctx.stack_size
          last = ctx.stack_size
        end
      end

      frames = (first...last).map do |i|
        frame = ::Byebug::Frame.new(ctx, i)
        ::DAP::StackFrame.new(
          id: @session.save_frame(ctx.thnum, i),
          name: frame_name(frame),
          source: ::DAP::Source.new(
            name: File.basename(frame.file),
            path: File.expand_path(frame.file)),
          line: frame.line,
          column: 0) # TODO real column
          .validate!
      end

      respond! body: ::DAP::StackTraceResponseBody.new(
        stackFrames: frames,
        totalFrames: ctx.stack_size)
    end

    private

    def frame_name(frame)
      frame.deco_call
    rescue
      frame.deco_block + frame.deco_class + frame.deco_method + "(?)"
    end
  end
end
