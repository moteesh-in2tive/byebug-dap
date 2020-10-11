module Byebug::DAP
  class Command::SetFunctionBreakpoints < Command
    # "Replaces all existing function breakpoints with new function breakpoints.
    # "To clear all function breakpoints, specify an empty array.
    # "When a function breakpoint is hit, a ‘stopped’ event (with reason ‘function breakpoint’) is generated.

    register!

    def execute
      ::Byebug.breakpoints.each { |bp| ::Byebug::Breakpoint.remove(bp.id) if bp.pos.is_a?(String) }

      existing = Byebug.breakpoints.filter { |bp| bp.pos.is_a?(String) }
      verified = []
      results = []

      args.breakpoints.each do |rq|
        m = /^(?<class>[:\w]+)(?<sep>\.|#)(?<method>\w+)$/.match(rq.name)
        unless m
          results << {
            verified: false,
            message: "'#{rq.name}' is not a valid method identifier",
          }
          next
        end

        bp = find_or_add_breakpoint(verified, existing, m[:class], m[:method])
        bp.expr = convert_breakpoint_condition(rq.condition)
        bp.hit_condition, bp.hit_value = convert_breakpoint_hit_condition(rq.hitCondition)
      end

      verified.each do |bp|
        cm, im = resolve_method(bp.source, bp.pos)

        if cm.nil? && im.nil?
          results << {
            id: bp.id,
            verified: true
          }
        end

        unless cm.nil?
          results << {
            id: bp.id,
            verified: true,
            source: ::DAP::Source.new(name: File.basename(cm[0]), path: cm[0]),
            line: cm[1]
          }
        end

        unless im.nil?
          results << {
            id: bp.id,
            verified: true,
            source: ::DAP::Source.new(name: File.basename(im[0]), path: im[0]),
            line: im[1]
          }
        end
      end

      @session.clear_breakpoints(*existing)

      respond! body: { breakpoints: results }
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
