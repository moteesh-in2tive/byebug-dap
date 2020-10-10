module Byebug::DAP
  class Command::SetFunctionBreakpoints < Command
    # "Replaces all existing function breakpoints with new function breakpoints.
    # "To clear all function breakpoints, specify an empty array.
    # "When a function breakpoint is hit, a ‘stopped’ event (with reason ‘function breakpoint’) is generated.

    register!

    def execute
      ::Byebug.breakpoints.each { |bp| ::Byebug::Breakpoint.remove(bp.id) if bp.pos.is_a?(String) }

      results = []
      args.breakpoints.each do |requested|
        m = /^(?<class>[:\w]+)(?<sep>\.|#)(?<method>\w+)$/.match(requested.name)
        unless m
          results << ::DAP::Breakpoint.new(
            verified: false,
            message: "'#{requested.name}' is not a valid method identifier")
        end

        bp = Byebug::Breakpoint.add(m[:class], m[:method].to_sym)
        next unless bp

        cm, im = resolve_method(m[:class], m[:method])

        if cm.nil? && im.nil?
          results << ::DAP::Breakpoint.new(
            id: bp.id,
            verified: true)
        end

        unless cm.nil?
          results << ::DAP::Breakpoint.new(
            id: bp.id,
            verified: true,
            source: ::DAP::Source.new(name: File.basename(cm[0]), path: cm[0]),
            line: cm[1])
        end

        unless im.nil?
          results << ::DAP::Breakpoint.new(
            id: bp.id,
            verified: true,
            source: ::DAP::Source.new(name: File.basename(im[0]), path: im[0]),
            line: im[1])
        end
      end

      respond! body: ::DAP::SetFunctionBreakpointsResponseBody.new(breakpoints: results)
    end

    private

    def resolve_method(class_name, method_name)
      scope = Object
      class_name.split('::').each do |n|
        scope = scope.const_get(n)
      rescue NameError
        return nil
      end

      class_method =
        begin
          scope.method(method_name)&.source_location
        rescue NameError
          nil
        end

      instance_method =
        begin
          scope.instance_method(method_name)&.source_location
        rescue NameError
          nil
        end

      return class_method, instance_method

    rescue StandardError => e
      LOG.puts "#{e.message} (#{e.class.name})", *e.backtrace if Debug.evaluate
      nil
    end
  end
end
