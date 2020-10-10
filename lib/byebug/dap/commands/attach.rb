module Byebug::DAP
  class Command::Attach < Command
    # "The attach request is sent from the client to the debug adapter to attach to a debuggee that is already running.

    register!

    def execute
      stopped!
      @session.start!(:attached)
      respond!
    end
  end
end
