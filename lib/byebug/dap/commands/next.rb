module Byebug::DAP
  class Command::Next < ContextualCommand
    # "The request starts the debuggee to run again for one step.
    # "The debug adapter first sends the response and then a ‘stopped’ event (with reason ‘step’) after the step has completed.

    register!

    def execute_in_context
      @context.step_over(1, @context.frame.pos)
      :stop
    end
  end
end
