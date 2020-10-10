module Byebug::DAP
  class Command::SetBreakpoints < Command
    # "Sets multiple breakpoints for a single source and clears all previous breakpoints in that source.
    # "To clear all breakpoint for a source, specify an empty array.
    # "When a breakpoint is hit, a ‘stopped’ event (with reason ‘breakpoint’) is generated.

    register!

    def execute
      unless File.exist?(args.source.path)
        # file doesn't exist, no breakpoints set
        respond! body: ::DAP::SetBreakpointsResponseBody.new(breakpoints: [])
        return
      end

      path = File.realpath(args.source.path)
      ::Byebug.breakpoints.each { |bp| ::Byebug::Breakpoint.remove(bp.id) if bp.source == path }

      lines = ::Byebug::Breakpoint.potential_lines(path)
      verified = []
      args.breakpoints.each do |requested|
        next unless lines.include? requested.line

        bp = ::Byebug::Breakpoint.add(path, requested.line)
        verified << ::DAP::Breakpoint.new(
          id: bp.id,
          verified: true,
          line: requested.line)
      end

      respond! body: ::DAP::SetBreakpointsResponseBody.new(breakpoints: verified)
    end
  end
end
