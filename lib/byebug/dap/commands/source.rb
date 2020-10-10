module Byebug::DAP
  class Command::Source < Command
    # "The request retrieves the source code for a given source reference.

    register!

    def execute
      path = args.source.path
      if File.readable?(path)
        respond! body: ::DAP::SourceResponseBody.new(content: IO.read(path))

      elsif File.exist?(path)
        respond! success: false, message: "Source file '#{path}' exists but cannot be read"

      else
        respond! success: false, message: "No source file available for '#{path}'"
      end
    end
  end
end
