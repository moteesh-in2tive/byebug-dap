module Byebug::DAP
  class Command::BreakpointLocations < Command
    # "The ‘breakpointLocations’ request returns all possible locations for source breakpoints in a given range.

    register!

    def execute
      return unless path = can_read_file!(args.source.path)
      lines = potential_breakpoint_lines(path) { |e|
        respond! success: false, message: "Failed to resolve breakpoints for #{path}"
        return
      }

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
