module Byebug::DAP
  class Command::StepIn < ContextualCommand
    # "The request starts the debuggee to step into a function/method if possible.
    # "If it cannot step into a target, ‘stepIn’ behaves like ‘next’.
    # "The debug adapter first sends the response and then a ‘stopped’ event (with reason ‘step’) after the step has completed.
    # "If there are multiple function/method calls (or other targets) on the source line,
    # "the optional argument ‘targetId’ can be used to control into which target the ‘stepIn’ should occur.
    # "The list of possible targets for a given source line can be retrieved via the ‘stepInTargets’ request.

    register!

    def execute
      super
      respond!
    end

    def execute_in_context
      @context.step_into(1, @context.frame.pos)
      :stop
    end
  end
end
