module Byebug::DAP
  class Command::Source < Command
    # "The request retrieves the source code for a given source reference.

    register!

    def execute
      if File.readable?(args.source.path)
        respond! body: ::DAP::SourceResponseBody.new(content: IO.read(args.source.path))

      elsif File.exist?(args.source.path)
        respond! success: false, message: "Source file '#{args.source.path}' exists but cannot be read"

      else
        respond! success: false, message: "No source file available for '#{args.source.path}'"
      end
    end
  end
end
