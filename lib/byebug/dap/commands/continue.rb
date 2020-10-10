module Byebug::DAP
  class Command::Continue < ContextualCommand
    # "The request starts the debuggee to run again.

    register!

    def execute_in_context
      :stop
    end
  end
end
