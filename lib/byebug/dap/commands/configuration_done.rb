module Byebug::DAP
  class Command::ConfigurationDone < Command
    # "This optional request indicates that the client has finished initialization of the debug adapter.

    register!

    def execute
      respond!
      @session.configured!
    end
  end
end
