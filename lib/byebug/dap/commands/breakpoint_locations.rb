module Byebug::DAP
  class Command::BreakpointLocations < Command
    # "The ‘breakpointLocations’ request returns all possible locations for source breakpoints in a given range.

    register!

    def execute
      unless File.readable?(args.source.path)
        if File.exist?(args.source.path)
          respond! success: false, message: "Source file '#{args.source.path}' exists but cannot be read"
        else
          respond! success: false, message: "No source file available for '#{args.source.path}'"
        end
        return
      end

      lines = Byebug::Breakpoint.potential_lines(args.source.path)
      unless args.endLine
        if lines.include?(args.line)
          respond! body: { breakpoints: [{ line: args.line }] }
        else
          respond! body: { breakpoints: [] }
        end
        return
      end

      range = [args.line..args.endLine]
      lines.filter! { |l| range.include?(l) }
      respond! body: { breakpoints: lines.map { |l| { line: l } } }
    end
  end
end
