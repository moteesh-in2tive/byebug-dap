module Byebug::DAP
  class Command::SetBreakpoints < Command
    # "Sets multiple breakpoints for a single source and clears all previous breakpoints in that source.
    # "To clear all breakpoint for a source, specify an empty array.
    # "When a breakpoint is hit, a ‘stopped’ event (with reason ‘breakpoint’) is generated.

    register!

    def execute
      return unless path = can_read_file!(args.source.path)
      if args.lines.empty? && args.breakpoints.empty?
        Byebug.breakpoints.reject! { |bp| bp.source == path }
        respond! body: { breakpoints: [] }
        return
      end

      existing = Byebug.breakpoints.filter { |bp| bp.source == path }
      verified = []
      lines = potential_breakpoint_lines(path) { |e|
        respond! success: false, message: "Failed to resolve breakpoints for #{path}"
        return
      }

      (args.lines & lines).each do |l|
        find_or_add_breakpoint(verified, existing, path, l)
      end

      args.breakpoints.filter { |rq| lines.include?(rq.line) }.each do |rq|
        bp = find_or_add_breakpoint(verified, existing, path, rq.line)
        bp.expr = convert_breakpoint_condition(rq.condition)
        bp.hit_condition, bp.hit_value = convert_breakpoint_hit_condition(rq.hitCondition)
        @session.set_log_point(bp, rq.logMessage)
      end

      @session.clear_breakpoints(*existing)

      respond! body: {
        breakpoints: verified.map { |bp|
          {
            id: bp.id,
            line: bp.pos,
            verified: true,
          }
        }
      }
    end
  end
end
