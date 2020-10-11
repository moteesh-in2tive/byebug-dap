module Byebug::DAP
  class Command::StepOut < ContextualCommand
    # "The request starts the debuggee to run again for one step.
    # "The debug adapter first sends the response and then a ‘stopped’ event (with reason ‘step’) after the step has completed.

    register!

    def execute
      super
      respond!
    end

    def execute_in_context
      @context.step_out(@context.frame.pos + 1, false)
      @context.frame = 0
      :stop
    end
  end
end
