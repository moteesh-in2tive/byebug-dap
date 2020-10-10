module Byebug::DAP
  class Command::Source < Command
    # "The request retrieves the source code for a given source reference.

    register!

    def execute
      return unless path = can_read_file!(args.source.path)
      respond! body: { content: IO.read(path) }
    end
  end
end
