module Byebug::DAP
  class Command::Pause < ContextualCommand
    # "The request suspends the debuggee.
    # "The debug adapter first sends the response and then a ‘stopped’ event (with reason ‘pause’) after the thread has been paused successfully.

    register!

    def execute_in_context
      @processor.pause_requested = true
    end

    private

    def forward_to_context(ctx)
      ctx.interrupt
      super
    end
  end
end
