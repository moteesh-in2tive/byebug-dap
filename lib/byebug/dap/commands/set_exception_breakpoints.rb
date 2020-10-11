module Byebug::DAP
  class Command::SetExceptionBreakpoints < Command
    # "The request configures the debuggers response to thrown exceptions.
    # "If an exception is configured to break, a ‘stopped’ event is fired (with reason ‘exception’).

    FILTERS = [
      {
        filter: 'standard',
        label: 'Standard errors',
      },
      {
        filter: 'all',
        label: 'All exceptions',
      },
    ]

    register!

    def execute
      Byebug.catchpoints.clear

      args.filters.each do |f|
        case f
        when 'standard'
          Byebug.add_catchpoint('StandardError')
        when 'all'
          Byebug.add_catchpoint('Exception')
        end
      end

      respond!
    end
  end
end
