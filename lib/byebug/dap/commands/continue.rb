module Byebug::DAP
  class Command::Continue < ContextualCommand
    # "The request starts the debuggee to run again.

    register!

    def execute_in_context
      :stop
    end

    private

    def forward_to_context(ctx)
      super
      respond!
    end
  end
end
