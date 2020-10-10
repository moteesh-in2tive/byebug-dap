module Byebug::DAP
  class Command::SetBreakpoints < Command
    # "Sets multiple breakpoints for a single source and clears all previous breakpoints in that source.
    # "To clear all breakpoint for a source, specify an empty array.
    # "When a breakpoint is hit, a ‘stopped’ event (with reason ‘breakpoint’) is generated.

    register!

    def execute
      return unless path = can_read_file!(args.source.path)
      lines = potential_breakpoint_lines(path) { |e|
        respond! success: false, message: "Failed to resolve breakpoints for #{path}"
        return
      }

      ::Byebug.breakpoints.each { |bp| ::Byebug::Breakpoint.remove(bp.id) if bp.source == path }

      verified = []
      args.breakpoints.each do |requested|
        next unless lines.include? requested.line

        bp = ::Byebug::Breakpoint.add(path, requested.line)
        verified << ::DAP::Breakpoint.new(
          id: bp.id,
          verified: true,
          line: requested.line)
      end

      respond! body: { breakpoints: verified }
    end
  end
end
