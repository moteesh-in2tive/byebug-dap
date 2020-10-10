module Byebug::DAP
  class Command::Launch < Command
    # "This launch request is sent from the client to the debug adapter to start the debuggee with or without debugging (if ‘noDebug’ is true).

    register!

    def execute
      stopped!
      @session.start!(:launched) unless args.noDebug
      respond!
    end
  end
end
